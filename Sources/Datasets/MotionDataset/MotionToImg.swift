import TensorFlow
import Foundation
import ModelSupport
import PythonKit

let plt = Python.import("matplotlib.pyplot")

extension Tensor where Scalar: NumpyScalarCompatible, Scalar: Numeric {
    public func paddedTo(padTo: Int = 500) -> Tensor {
        let rank = self.shape.count
        let currentWidth = self.shape[0]
        let paddingSize = Swift.max(padTo - currentWidth, 0)
        var sizes: [(before: Int, after: Int)] = [(before: 0, after: paddingSize)]
        if rank > 1 {
            sizes.append((before: 0, after: 0))
        }        
        let tensor = self.padded(forSizes: sizes, with: 0)
        return tensor
    }
}

public func motionToImg(url: URL?, motion: Tensor<Float>, motionFlag: Tensor<Int32>?, padTo: Int = 500, descr: String = "", cmapRange: Double = 2) {
    let motion = motion.paddedTo(padTo: padTo)
    var joined: Tensor<Float>
    if motionFlag != nil {
        let motionFlag = motionFlag!.paddedTo(padTo: padTo)
        let motionFlag2 = Tensor<Float>(motionFlag).expandingShape(at: 1)*motion.max()
        joined = Tensor(concatenating: [motionFlag2, motion], alongAxis: 1)
    } else {
        joined = motion
    }
    
    let x = plt.subplots()
    let ax = x[1]
    // cmaps: viridis, gist_rainbow, bwr, seismic, coolwarm, hsv, plasma*, PRGn, twilight_shifted, Spectral...
    ax.imshow(joined.makeNumpyArray().T, extent: [0, padTo, 0, joined.shape[1]], cmap: "Spectral", vmin: -cmapRange, vmax: cmapRange)
    ax.set_title("\(descr)")
    if url != nil {
        plt.savefig(url!.path)
    }
    plt.show()
}
