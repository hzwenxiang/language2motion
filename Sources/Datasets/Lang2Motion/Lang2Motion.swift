import Foundation
import ModelSupport
import TensorFlow
import PythonKit

public struct Lang2Motion {

    public struct LangRec {
        public let sampleID: Int
        public let text: String
        public let motionSample: MotionSample
    }

    public let motionDataset: MotionDataset
    public let scaler: Scaler

    public let motionSamples: [MotionSample]
    public let langRecs: [LangRec]

    public let motionSampleDict: [Int: MotionSample]

    public let trainMotionSamples: [MotionSample]
    public let testMotionSamples: [MotionSample]

    public typealias LazySamples = LazyMapSequence<[MotionSample], LangMotionBatch>

    public let batchSize: Int

    /// The type of the collection of batches.
    public typealias Batches = Slices<Sampling<LazySamples, ArraySlice<Int>>>
    /// The type of the training sequence of epochs.
    public typealias TrainEpochs = LazyMapSequence<TrainingEpochs<LazySamples, SystemRandomNumberGenerator>, 
        LazyMapSequence<Batches, LangMotionBatch>>
    /// The sequence of training data (epochs of batches).
    public var trainEpochs: TrainEpochs
    /// The test batches.
    public var testBatches: LazyMapSequence<Slices<LazySamples>, LangMotionBatch>
}

extension Lang2Motion {

    public static func demultiplyMotionSamples(_ motionSamples: [MotionSample]) -> [MotionSample] {
        var _uniqueMotionSampleDict: [Int: MotionSample] = [:]
        for ms in motionSamples {
            // only assign first (downsampled) sample
            if _uniqueMotionSampleDict[ms.sampleID] == nil {
                _uniqueMotionSampleDict[ms.sampleID] = ms
            }
        }
        return _uniqueMotionSampleDict.map { $0.value }
    }

    public init(
        motionDatasetURL: URL,
        batchSize: Int,
        minMotionLength: Int = 10,
        maxMotionLength: Int = 100,
        trainTestSplit: Double = 0.8,
        demultiplyMotions: Bool = false,
        device: Device,
        exampleMap: @escaping (MotionSample) -> LangMotionBatch
    ) throws {
        // Load the data files.
        motionDataset = MotionDataset(from: motionDatasetURL)
        print(motionDataset.description)

        // filter out samples without annotations
        var _motionSamples = motionDataset.motionSamples.filter { $0.annotations.count > 0 }
        print("Keeping \(_motionSamples.count) annotated motions.")

        // filter out shortest samples
        _motionSamples = _motionSamples.filter { $0.motion.shape[0] >= minMotionLength }
        print("Keeping \(_motionSamples.count) longer motions, with minimum \(minMotionLength) frames.")

        // filter out longest samples
        _motionSamples = _motionSamples.filter { $0.motion.shape[0] <= maxMotionLength }
        print("Keeping \(_motionSamples.count) shorter motions, with maximum \(maxMotionLength) frames.")

        // filter out multiplied motions
        if demultiplyMotions {
            _motionSamples = Self.demultiplyMotionSamples(_motionSamples)
            print("Demultiplaying motions back to \(_motionSamples.count).")
        }

        // scale motions
        print("Scaling motions...")
        let motions = _motionSamples.map { $0.motion }
        let _scaler = Scaler(X: Tensor(concatenating: motions, alongAxis: 0))
        let scaledMotions = motions.map { _scaler.transform($0) }

        for idx in 0..<_motionSamples.count {
            _motionSamples[idx].motion = scaledMotions[idx]
        }
        scaler = _scaler
        print("Motions scaled.")

        // get all annotations from motionSamples
        var _motionSamplesWithDistinctAnnotations: [MotionSample] = []

        for ms in _motionSamples {
            let samples = ms.annotations.map { (ann: String) -> MotionSample in
                MotionSample(sampleID: ms.sampleID, annotations: [ann], jointNames: ms.jointNames, timesteps: ms.timesteps, motion: ms.motion) 
            }
            _motionSamplesWithDistinctAnnotations.append(contentsOf: samples)
        }
        print("Having \(_motionSamplesWithDistinctAnnotations.count) annotations with motions.")

        motionSamples = _motionSamplesWithDistinctAnnotations

        // create LangRecs
        langRecs = _motionSamplesWithDistinctAnnotations.map { LangRec(sampleID: $0.sampleID, text: $0.annotations[0], motionSample: $0) }

        // [sampleID:MotionSample] mapping
        var _motionSampleDict: [Int: MotionSample] = [:]
        for ms in motionDataset.motionSamples {
            // only assign first (downsampled) sample
            if _motionSampleDict[ms.sampleID] == nil {
                _motionSampleDict[ms.sampleID] = ms
            }
        }
        motionSampleDict = _motionSampleDict

        // split into train/test sets
        let _trainMotionSamples: [MotionSample]
        let _testMotionSamples: [MotionSample]
        (_trainMotionSamples, _testMotionSamples) = _motionSamplesWithDistinctAnnotations.trainTestSplitMotionSamples(split: trainTestSplit)
        trainMotionSamples = _trainMotionSamples
        testMotionSamples = _testMotionSamples

        let trainSamples: LazySamples = _trainMotionSamples.lazy.map(exampleMap)
        let testSamples: LazySamples = _testMotionSamples.lazy.map(exampleMap)

        self.batchSize = batchSize

        // Create the training sequence of epochs.
        let entropy = SystemRandomNumberGenerator()
        trainEpochs = TrainingEpochs(
        samples: trainSamples, batchSize: batchSize, entropy: entropy
        ).lazy.map { (batches: Batches) -> LazyMapSequence<Batches, LangMotionBatch> in
            batches.lazy.map{ 
                // TODO: reduceDataBatches to device directly
                LangMotionBatch(copying: LangMotionBatch.reduceDataBatches(Array($0)), to: device)
            }
        }
        
        // Create the test collection of batches.
        testBatches = testSamples.inBatches(of: batchSize).lazy.map{ 
                LangMotionBatch(copying: LangMotionBatch.reduceDataBatches(Array($0)), to: device)
        }
    }
}
