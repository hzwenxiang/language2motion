import Foundation
import TensorFlow
import ModelSupport

public typealias LangMotionBatch = LabeledData<LangMotion.Source, LangMotion.Target>

public struct LangMotion {

    public struct Sentence {
        public var tokenIds: Tensor<Int32>   // bs x maxTextSequenceLength
        public var mask: Tensor<Float>       // bs x 1 x maxTextSequenceLength
        public let tokenCount: Tensor<Int32> // bs

        public init(tokenIds: Tensor<Int32>, mask: Tensor<Float>, tokenCount: Tensor<Int32>) {
            self.tokenIds = tokenIds
            self.mask = mask
            self.tokenCount = tokenCount
        }

        public init(copying sentence: Sentence, to device: Device) {
            tokenIds = Tensor<Int32>(copying: sentence.tokenIds, to: device)
            mask = Tensor<Float>(copying: sentence.mask, to: device)
            tokenCount = Tensor<Int32>(copying: sentence.tokenCount, to: device)
        }

        public func printSentence() {
            print("sentence")
            print("  tokenIds.shape: \(self.tokenIds.shape)")
            print("  mask.shape: \(self.mask.shape)")
            print("  tokenCount: shape \(self.tokenCount.shape), value \(self.tokenCount)")
        }
    }

    public struct MotionPart {
        public var motion: Tensor<Float>          // bs x maxMotionLength-1 x nbJoints
        public var mask: Tensor<Float>            // bs x maxMotionLength-1 x maxMotionLength-1

        public init(motion: Tensor<Float>, mask: Tensor<Float>) {
            self.motion = motion
            self.mask = mask
        }

        public init(copying motionPart: MotionPart, to device: Device) {
            motion = Tensor<Float>(copying: motionPart.motion, to: device)
            mask = Tensor<Float>(copying: motionPart.mask, to: device)
        }

        public func printMotionPart() {
            print("motionPart")
            print("  motion.shape: \(self.motion.shape)")
            print("  mask.shape: \(self.mask.shape)")
        }
    }

    public struct Source {
        public var sentence: Sentence
        public var motionPart: MotionPart

        public init(sentence: Sentence, motionPart: MotionPart) {
            self.sentence = sentence
            self.motionPart = motionPart
        }

        public init(copying source: Source, to device: Device) {
            sentence = Sentence(copying: source.sentence, to: device)
            motionPart = MotionPart(copying: source.motionPart, to: device)
        }

        public func printSource() {
            print("source")
            print("  sentence")
            print("    tokenIds.shape: \(self.sentence.tokenIds.shape)")
            print("    mask.shape: \(self.sentence.mask.shape)")
            print("    tokenCount: (shape: \(self.sentence.tokenCount.shape), value: \(self.sentence.tokenCount))")
            print("  motionPart")
            print("    motion.shape: \(self.motionPart.motion.shape)")
            print("    mask.shape: \(self.motionPart.mask.shape)")
        }
    }

    // Target
    public struct Target {
        public let sampleID: Tensor<Int32>        // bs

        public var motion: Tensor<Float>          // bs x maxMotionLength-1 x nbJoints
        public var stops: Tensor<Float>           // bs x maxMotionLength-1

        public let origMotionFramesCount: Tensor<Int32> // bs

        public init(sampleID: Tensor<Int32>, motion: Tensor<Float>, stops: Tensor<Float>, origMotionFramesCount: Tensor<Int32>) {
            self.sampleID = sampleID

            self.motion = motion
            self.stops = stops
            self.origMotionFramesCount = origMotionFramesCount
        }

        public init(copying target: Target, to device: Device) {
            sampleID = Tensor<Int32>(copying: target.sampleID, to: device)

            motion = Tensor<Float>(copying: target.motion, to: device)
            stops = Tensor<Float>(copying: target.stops, to: device)
            origMotionFramesCount = Tensor<Int32>(copying: target.origMotionFramesCount, to: device)
        }

        public func printTarget() {
            print("target")
            print("  sampleID: (shape: \(self.sampleID.shape), value: \(self.sampleID))")

            print("  motion.shape: \(self.motion.shape)")
            print("  stops.shape: \(self.stops.shape)")
            print("  origMotionFramesCount: (shape: \(self.origMotionFramesCount.shape), value: \(self.origMotionFramesCount))")
        }
    }
}

extension LangMotionBatch {
    public typealias Source = LangMotion.Source
    public typealias Sentence = LangMotion.Sentence
    public typealias MotionPart = LangMotion.MotionPart
    public typealias Target = LangMotion.Target

    public var source: Source { get { return data } }
    public var target: Target { get { return label } }

    public init(source: Source, target: Target) {
        self.init(data: source, label: target)
    }

    public init(copying batch: LangMotionBatch, to device: Device) {
        let data = Source(copying: batch.data, to: device)
        let label = Target(copying: batch.label, to: device)
        self.init(data: data, label: label)
    }

    public static func reduceDataBatches(_ batches: [LangMotionBatch]) -> LangMotionBatch {
        let tokenIds: Tensor<Int32> = Tensor(batches.map{ $0.data.sentence.tokenIds.squeezingShape(at: 0) })
        let mask: Tensor<Float> = Tensor(batches.map{ $0.data.sentence.mask.squeezingShape(at: 0) })
        let tokenCount: Tensor<Int32> = Tensor(batches.map{ $0.data.sentence.tokenCount.squeezingShape(at: 0) })
        let motionPartTensor: Tensor<Float> = Tensor(batches.map{ $0.data.motionPart.motion.squeezingShape(at: 0) })
        let motionPartMask: Tensor<Float> = Tensor(batches.map{ $0.data.motionPart.mask.squeezingShape(at: 0) })

        let sampleID: Tensor<Int32> = Tensor(batches.map{ $0.label.sampleID.squeezingShape(at: 0) })
        let targetMotion: Tensor<Float> = Tensor(batches.map{ $0.label.motion.squeezingShape(at: 0) })
        let targetStops: Tensor<Float> = Tensor(batches.map{ $0.label.stops.squeezingShape(at: 0) })
        let origMotionFramesCount: Tensor<Int32> = Tensor(batches.map{ $0.label.origMotionFramesCount.squeezingShape(at: 0) })

        let sentence = Sentence(tokenIds: tokenIds, mask: mask, tokenCount: tokenCount)
        let motionPart = MotionPart(motion: motionPartTensor, mask: motionPartMask)
        let data = Source(sentence: sentence, motionPart: motionPart)
        let label = Target(sampleID: sampleID, motion: targetMotion, stops: targetStops, origMotionFramesCount: origMotionFramesCount)
        let batch = LangMotionBatch(data: data,label: label)

        return batch
    }

    public static func preprocessTargetMotion(sampleID: Int, motion: Tensor<Float>, maxMotionLength: Int) -> (motionPart: MotionPart, target: Target)
    {
        let origMotionFramesCount: Tensor<Int32> = Tensor<Int32>([Int32(motion.shape[0])])

        var (paddedMotion, motionFlag) = motion.paddedAndCropped(to: maxMotionLength)
        paddedMotion = paddedMotion.expandingShape(at: 0)
        motionFlag = motionFlag.expandingShape(at: 0)

        // source (motionPart & motion flag)
        let rangeExceptLast = 0..<(paddedMotion.shape[1] - 1)
        let motionPartTensor = paddedMotion[0..., rangeExceptLast, 0...]

        let motionPartFlag = motionFlag[0..., rangeExceptLast]
        let motionPartMask = makeStandardMask(target: motionPartFlag, pad: 0) // FIXME: fix target mask

        let motionPart = MotionPart(motion: motionPartTensor, mask: motionPartMask)

        // target (motion & stops)
        let targetMotion: Tensor<Float> = paddedMotion[0..., 1..., 0...]
        let targetMotionFlag = motionFlag[0..., 1...]
        let targetStops: Tensor<Float> = 1.0 - Tensor<Float>(targetMotionFlag)

        let target = Target(sampleID: Tensor([Int32(sampleID)]), motion: targetMotion, stops: targetStops, origMotionFramesCount: origMotionFramesCount)
        return (motionPart: motionPart, target: target)
    }

    public static func subsequentMask(size: Int) -> Tensor<Int32> {
        let attentionShape = [1, size, size]
        return Tensor<Int32>(ones: TensorShape(attentionShape))
            .bandPart(subdiagonalCount: 0, superdiagonalCount: -1)
    }

    public static func makeStandardMask(target: Tensor<Int32>, pad: Int32) -> Tensor<Float> {
        var targetMask = Tensor(zerosLike: target)
            .replacing(with: Tensor(onesLike: target), where: target .!= Tensor.init(pad))
            .expandingShape(at: -2)
        targetMask *= subsequentMask(size: target.shape.last!)
        return Tensor<Float>(targetMask)
    }
}
