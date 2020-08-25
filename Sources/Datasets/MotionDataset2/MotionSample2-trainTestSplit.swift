extension Collection where Iterator.Element == MotionSample2 {
    func motionSamplesWithIds(_ sampleIds: [Int], mapping: [Int: [Int]]) -> [MotionSample2] {
        var motionSamples: [MotionSample2] = []
        for sampleId in sampleIds {
            let idxs = mapping[sampleId]
            for idx in idxs! {
                motionSamples.append(self[idx as! Self.Index])
            }
        }
        return motionSamples
    }
    
    
    public func trainTestSplitMotionSamples(split: Double) -> (train: Array<Element>, test: Array<Element>) {
        // splits multiplied samples into train/test buckets, making sure that samples with same ids end up in same bucket
        let allSampleIds = self.map {$0.sampleID}
        let sampleIds = Array(Set(allSampleIds)).sorted()
        let (trainSampleIds, testSampleIds) = sampleIds.trainTestSplit(split: split)
        var mapping: [Int: [Int]] = [:] // sampleIds -> [collection indices]
        for sampleId in sampleIds {
            mapping[sampleId] = []
        }
        for (idx, sampleId) in allSampleIds.enumerated() {
            mapping[sampleId]!.append(idx)
        }
        let trainMotionSamples = motionSamplesWithIds(trainSampleIds, mapping: mapping)
        let testMotionSamples = motionSamplesWithIds(testSampleIds, mapping: mapping)
        return (trainMotionSamples, testMotionSamples)
    }
}
