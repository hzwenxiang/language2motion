import Foundation
import ModelSupport
import TensorFlow
import PythonKit


public struct Motion2Lang {

    public struct LangRec {
        public let sampleID: Int
        public let text: String
        public let label: String
    }

    /// Motion2Lang example.
    public struct Example {
        public let id: String
        public let motionSample: LegacyMotionSample
        public let targetSentence: String

        public init(id: String, motionSample: LegacyMotionSample, targetSentence: String) {
            self.id = id
            self.motionSample = motionSample
            self.targetSentence = targetSentence
        }
    }

    public let motionDataset: LegacyMotionDataset

    public let langRecs: [LangRec]
    public let langRecsDict: [Int: LangRec]

    public let motionSampleDict: [Int: LegacyMotionSample]

    public let trainExamples: [Example]
    public let valExamples: [Example]

    public typealias Samples = LazyMapSequence<[Example], MotionLangBatch>

    /// The training texts.
    public let trainingSamples: Samples
    /// The validation texts.
    public let validationSamples: Samples
    // public let validationSamples: [(text: String, label: String)]

    /// The sequence length to which every sentence will be padded.
    public let maxSequenceLength: Int
    public let batchSize: Int

    /// The type of the collection of batches.
    public typealias Batches = Slices<Sampling<Samples, ArraySlice<Int>>>
    /// The type of the training sequence of epochs.
    public typealias TrainEpochs = LazyMapSequence<TrainingEpochs<Samples, SystemRandomNumberGenerator>, 
        LazyMapSequence<Batches, MotionLangBatch>>
    /// The sequence of training data (epochs of batches).
    public var trainingEpochs: TrainEpochs
    /// The validation batches.
    public var validationBatches: LazyMapSequence<Slices<Samples>, MotionLangBatch>    
}

//===-----------------------------------------------------------------------------------------===//
// Data
//===-----------------------------------------------------------------------------------------===//

extension Motion2Lang {
    static func transformDF(df: PythonObject) -> [LangRec] {
        return Python.list(df.iterrows()).map {
            (rowObj: PythonObject) -> LangRec in 
            let row = rowObj.tuple2.1
            let sample_id: Int = Int(row.sample_id)!
            let text: String = String(row.text)!
            let label: String = String(row.label)!
            return LangRec(sampleID: sample_id, text: text, label: label)
        }
    }

    public static func getExample(motionSample: LegacyMotionSample, langRec: LangRec) -> Example {
        let sample_id: String = "\(langRec.sampleID)" // Int to String
        return Example(id: sample_id, motionSample: motionSample, targetSentence: langRec.text)
    }
}

extension Motion2Lang {
    /// Creates an instance of `motionDatasetURL` motion dataset with `langDatasetURL` labels,
    /// with batches of size `batchSize` by `maximumSequenceLength`.
    ///
    /// - Parameters:
    ///   - exampleMap: a transform that processes `Example` in `MotionLangBatch`.
    public init(
        motionDatasetURL: URL,
        langDatasetURL: URL,
        maxSequenceLength: Int, // TODO: separate motion length from text sequence length?
        batchSize: Int,
        minMotionLength: Int = 10,
        trainTestSplit: Double = 0.8,
        exampleMap: @escaping (Example) -> MotionLangBatch
    ) throws {
        // Load the data files.
        motionDataset = LegacyMotionDataset(from: motionDatasetURL)
        print(motionDataset.description)
        let df = pd.read_csv(langDatasetURL.path)

        // filter out samples without annotations
        var motionSamples = motionDataset.motionSamples.filter { $0.annotations.count > 0 }
        print("keeping \(motionSamples.count) annotatated motions")

        // filter out shortest samples
        motionSamples = motionSamples.filter { $0.motionFramesArray.shape[0] >= minMotionLength }
        print("keeping \(motionSamples.count) longer motions, with minimum \(minMotionLength) frames")

        // split into train/test sets
        var trainMotionSamples: [LegacyMotionSample] = []
        var testMotionSamples: [LegacyMotionSample] = []
        (trainMotionSamples, testMotionSamples) = motionSamples.trainTestSplitMotionSamples(split: trainTestSplit)

        // create LangRecs
        let _langRecs = Motion2Lang.transformDF(df: df)

        // [sampleID:LangRec] mapping
        var _langRecsDict: [Int: LangRec] = [:]
        for langRec in _langRecs {
            _langRecsDict[langRec.sampleID] = langRec
        }

        langRecs = _langRecs
        langRecsDict = _langRecsDict

        // [sampleID:LegacyMotionSample] mapping
        var _motionSampleDict: [Int: LegacyMotionSample] = [:]
        for ms in motionDataset.motionSamples {
            // only assign first (downsampled) sample
            if _motionSampleDict[ms.sampleID] == nil {
                _motionSampleDict[ms.sampleID] = ms
            }
        }
        motionSampleDict = _motionSampleDict

        // create Examples
        trainExamples = trainMotionSamples.map {
            Motion2Lang.getExample(motionSample: $0, langRec: _langRecsDict[$0.sampleID]!)
        }
        valExamples = testMotionSamples.map {
            Motion2Lang.getExample(motionSample: $0, langRec: _langRecsDict[$0.sampleID]!)
        }

        trainingSamples = trainExamples.lazy.map(exampleMap)
        validationSamples = valExamples.lazy.map(exampleMap)
      
        self.maxSequenceLength = maxSequenceLength
        self.batchSize = batchSize

        // Create the training sequence of epochs.
        let entropy = SystemRandomNumberGenerator()
        trainingEpochs = TrainingEpochs(
        samples: trainingSamples, batchSize: batchSize, entropy: entropy
        ).lazy.map { (batches: Batches) -> LazyMapSequence<Batches, MotionLangBatch> in
            batches.lazy.map{ 
                Motion2Lang.reduceDataBatches(Array($0))
            }
        }
        
        // Create the validation collection of batches.
        validationBatches = validationSamples.inBatches(of: batchSize).lazy.map{ 
            Motion2Lang.reduceDataBatches(Array($0))
        }
    }

    public static func reduceDataBatches(_ batches: [MotionLangBatch]) -> MotionLangBatch {
        var maxLength: Int? = 50 // FIXME: move this out
        maxLength = maxLength ?? batches.map { $0.motionFrames.shape[1] }.max()!

        let motionFrames: Tensor<Float> = Tensor(batches.map{$0.motionFrames.paddedOrCropped(to: maxLength!)})

        // let mask: Tensor<Float> = Tensor(batches.map{$0.mask.paddedOrCropped(to: maxLength!)})        
        // getting mask from motionFrames, so it's
        let mask: Tensor<Float> = motionFrames[0...,0...,LegacyMotionFrame.cjpMotionFlagIdx].expandingShape(at: 1)

        // let mask: Tensor<Float> = Tensor(batches.map{ $0.mask.squeezingShape(at: 0) })
        let origMotionFramesCount: Tensor<Int32> = Tensor(batches.map{$0.origMotionFramesCount})

        let targetTokenIds: Tensor<Int32> = Tensor(batches.map{ $0.targetTokenIds.squeezingShape(at: 0) })
        let targetMask: Tensor<Float> = Tensor(batches.map{ $0.targetMask.squeezingShape(at: 0) })
        let targetTruth: Tensor<Int32> = Tensor(batches.map{ $0.targetTruth.squeezingShape(at: 0) })
        return MotionLangBatch(motionFrames: motionFrames, 
                        mask: mask,
                        origMotionFramesCount: origMotionFramesCount,
                        targetTokenIds: targetTokenIds,
                        targetMask: targetMask,
                        targetTruth: targetTruth)
    }
}
