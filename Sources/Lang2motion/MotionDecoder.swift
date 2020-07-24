import TensorFlow
import PythonKit

let np  = Python.import("numpy")

func randomNumber(probabilities: [Double]) -> Int {
    // https://stackoverflow.com/questions/30309556/generate-random-numbers-with-a-given-distribution
    // Sum of all probabilities (so that we don't have to require that the sum is 1.0):
    let sum = probabilities.reduce(0, +)
    // Random number in the range 0.0 <= rnd < sum :
    let rnd = Double.random(in: 0.0 ..< sum)
    // Find the first interval of accumulated probabilities into which `rnd` falls:
    var accum = 0.0
    for (i, p) in probabilities.enumerated() {
        accum += p
        if rnd < accum {
            return i
        }
    }
    // This point might be reached due to floating point inaccuracies:
    return (probabilities.count - 1)
}

func gaussian_pdf(sample: Tensor<Float>, means: Tensor<Float>, variances: Tensor<Float>) -> Tensor<Float> {
    // one-dim tensors
    assert(sample.shape.count == 1)
    assert(sample.shape == means.shape)
    assert(sample.shape == variances.shape)
    let a1 = sqrt(Float(2.0) * Float(np.pi)! * variances)
    let a2 = -(sample - means).squared()
    return Float(1.0) / a1 * exp(a2 / (2.0 * variances))
}

func bernoulli_pdf(sample: Int, p: Float) -> Float {
    let fSample = Float(sample)
    return fSample * p + Float(1.0 - fSample) * (1.0 - p)
}

// TODO: simplify input params
// TODO: add output names to a tuple
func performNormalMixtureSampling(preds: Tensor<Float>, decoder: Any, nb_joints: Int, 
                                  previous_outputs: [[Tensor<Float>]], log_probabilities: [Float],
                                  done: [Bool], nb_mixtures: Int) -> ([[Tensor<Float>]], [Float], [Bool]) {
    var _log_probabilities = log_probabilities
    var _done = done
    let TINY: Float = 1e-8
    let _preds = preds.reshaped(to:
        [preds.shape[0], 2 * nb_joints * nb_mixtures + nb_mixtures + 1])
    let all_means = _preds[0..., 0..<nb_joints * nb_mixtures]
    let all_variances = _preds[0..., nb_joints *
                              nb_mixtures..<2 * nb_joints * nb_mixtures] + TINY
    let weights = _preds[0..., 2 * nb_joints * nb_mixtures..<2 *
                        nb_joints * nb_mixtures + nb_mixtures]
    assert(all_means.shape[-1] == nb_joints * nb_mixtures)
    assert(all_variances.shape[-1] == nb_joints * nb_mixtures)
    assert(weights.shape[-1] == nb_mixtures)
    let stops = _preds[0..., -1]

    /// Sample joint values.
    var samples = Tensor<Float>(zeros: [_preds.shape[0], nb_joints])
    var means = Tensor<Float>(zeros: [_preds.shape[0], nb_joints])
    var variances = Tensor<Float>(zeros: [_preds.shape[0], nb_joints])
    for width_idx in 0..<_preds.shape[0] {
        // Decide which mixture to sample from
        let p = weights[width_idx].scalars.map { Double($0)}
        assert(p.count == nb_mixtures)
        let mixture_idx = randomNumber(probabilities: p) //np.random.choice(range(nb_mixtures), p=p)

        /// Sample from it.
        let start_idx = mixture_idx * nb_joints
        let m = all_means[width_idx, start_idx..<start_idx + nb_joints]
        let v = all_variances[width_idx, start_idx..<start_idx + nb_joints]
        assert(m.shape == [nb_joints])
        assert(m.shape == v.shape)
        // https://numpy.org/doc/stable/reference/random/generated/numpy.random.normal.html
        let s = np.random.normal(m.scalars, v.scalars)
        samples[width_idx, 0...] = Tensor(numpy: s)!
        means[width_idx, 0...] = m
        variances[width_idx, 0...] = v
    }

    var _previous_outputs = previous_outputs
    // for idx, (sample, stop) in enumerate(zip(samples, stops)):
    for idx in 0..<samples.shape[0] {
        let sample = samples[idx]
        let stop: Float = stops[idx].scalar!
        if done[idx] {
            continue
        }
        // https://docs.scipy.org/doc/numpy-1.14.0/reference/generated/numpy.random.binomial.html
        let sampled_stop: Int = Int(np.random.binomial(n: 1, p: stop))!
        let combined = Tensor<Float>(concatenating: [sample, Tensor<Float>([Float(sampled_stop)])])
        assert(combined.shape == [nb_joints + 1])
        _previous_outputs[idx].append(combined)

        _log_probabilities[idx] += log(gaussian_pdf(sample: sample, means: means[idx], variances: variances[idx])).sum().scalar!
        _log_probabilities[idx] += log(bernoulli_pdf(sample: sampled_stop, p: stop))
        _done[idx] = (sampled_stop == 0)
    }
    return (_previous_outputs, _log_probabilities, _done)
}

func decode(context: Any, nb_joints: Int, language: Any, references: Any, args: Any, init: Any? = nil) {
// def decode(context, nb_joints, language, references, args, init=None):
    // # Prepare data structures for graph search.
    // if init is None:
    //     init = np.ones(nb_joints + 1)
    // assert init.shape == (nb_joints + 1,)
    // previous_outputs = [[np.copy(init)] for _ in range(args.width)]
    // repeated_context = np.repeat(context.reshape(
    //     1, context.shape[-1]), args.width, axis=0)
    // repeated_context = repeated_context.reshape(
    //     args.width, 1, context.shape[-1])
    // log_probabilities = [0. for _ in range(args.width)]
    // done = [False for _ in range(args.width)]

    // # Reset the decoder.
    // v_decoder_hidden = Variable(torch.zeros(decoder.n_layers, args.width, decoder.dec_hidden_size, dtype=torch.float32))

    // # Iterate over time.
    // predictions = [[] for _ in range(args.width)]

    // for _ in range(args.depth):
    //     previous_output = np.array([o[-1] for o in previous_outputs])
    //     assert previous_output.ndim == 2
    //     previous_output = previous_output.reshape(
    //         (previous_output.shape[0], 1, previous_output.shape[1]))
    //     t_repeated_context = torch.Tensor(repeated_context.squeeze(axis=1))
    //     t_previous_output = torch.Tensor(previous_output.squeeze(axis=1))
    //     t_encoder_outputs = torch.Tensor(encoder_outputs.detach().numpy().repeat(args.width, 1))
    //     decoder_output, v_decoder_hidden, decoder_attn = \
    //         decoder(t_repeated_context, t_previous_output, v_decoder_hidden, t_encoder_outputs)
    //     preds = np.expand_dims(decoder_output.detach().numpy(), axis=1)
    //     assert preds.shape[0] == args.width
    //     for idx, (pred, d) in enumerate(zip(preds, done)):
    //         if d:
    //             continue
    //         predictions[idx].append(pred)

    //     # Perform actual decoding.
    //     if args.decoder == 'normal':
    //         fn = perform_normal_sampling
    //     elif args.decoder == 'regression':
    //         fn = perform_regression
    //     elif args.decoder == 'normal-mixture':
    //         fn = perform_normal_mixture_sampling
    //     else:
    //         fn = None
    //         raise ValueError('Unknown decoder "{}"'.format(args.decoder))
    //     previous_outputs, log_probabilities, done = fn(
    //         preds, decoder, nb_joints, previous_outputs, log_probabilities, done, args)

    //     if args.motion_representation == 'hybrid':
    //         # For each element of the beam, add the new delta (index -1) to the previous element (index -2)
    //         # to obtain the absolute motion.
    //         for po in previous_outputs:
    //             po[-1][:nb_joints] = po[-2][:nb_joints] + po[-1][:nb_joints]
        
    //     # Check if we're done before reaching `args.depth`.
    //     if np.all(done):
    //         break

    // # Convert to numpy arrays.
    // predictions = [np.array(preds)[:, 0, :].astype('float32')
    //                for preds in predictions]

    // hypotheses = []
    // for previous_output in previous_outputs:
    //     motion = np.array(previous_output)[1:].astype(
    //         'float32')  # remove init state
    //     if args.motion_representation == 'diff':
    //         motion[:, :nb_joints] = np.cumsum(motion[:, :nb_joints], axis=0)
    //     assert motion.shape[-1] == nb_joints + 1
    //     hypotheses.append(motion.astype('float32'))

    // # Record data.
    // data = {
    //     'hypotheses': hypotheses,
    //     'log_probabilities': log_probabilities,
    //     'references': references,
    //     'language': language,
    //     'predictions': predictions,
    // }
    // return data
}