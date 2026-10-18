// Browser capabilities owned by the demo host, never by sai_nodes itself.
(() => {
  const shaders = new WeakMap();
  let audioContext, voice, audioTimer;
  const state = {shader: null, audio: null};
  function stopAudio() {
    clearTimeout(audioTimer);
    if (voice) {
      try { voice.oscillator.stop(); } catch (_) { /* already stopped */ }
      voice.oscillator.disconnect(); voice.gain.disconnect(); voice.filter.disconnect();
      voice = null;
    }
    if (state.audio) state.audio.active = false;
  }
  function stopShader(canvas) {
    const current = shaders.get(canvas);
    if (!current) return;
    cancelAnimationFrame(current.frame);
    current.gl.deleteBuffer(current.buffer);
    current.gl.deleteProgram(current.program);
    shaders.delete(canvas);
  }
  function renderShader(canvas, source) {
    stopShader(canvas);
    const gl = canvas.getContext('webgl', {antialias: false, preserveDrawingBuffer: true});
    if (!gl) { state.shader = {ok: false}; return 'WebGL is unavailable in this browser.'; }
    let vertex, fragment, program, buffer;
    try {
      function compile(type, code) {
        const shader = gl.createShader(type);
        gl.shaderSource(shader, code); gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
          const error = gl.getShaderInfoLog(shader); gl.deleteShader(shader); throw new Error(error);
        }
        return shader;
      }
      vertex = compile(gl.VERTEX_SHADER, 'attribute vec2 position; void main() { gl_Position = vec4(position, 0., 1.); }');
      fragment = compile(gl.FRAGMENT_SHADER, source);
      program = gl.createProgram(); gl.attachShader(program, vertex); gl.attachShader(program, fragment); gl.linkProgram(program);
      if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program));
      gl.deleteShader(vertex); vertex = null; gl.deleteShader(fragment); fragment = null;
      buffer = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, -1,1, 1,-1, 1,1]), gl.STATIC_DRAW);
      gl.useProgram(program);
      const position = gl.getAttribLocation(program, 'position');
      gl.enableVertexAttribArray(position); gl.vertexAttribPointer(position, 2, gl.FLOAT, false, 0, 0);
      const time = gl.getUniformLocation(program, 'u_time'), resolution = gl.getUniformLocation(program, 'u_resolution');
      const current = {gl, program, buffer, frame: 0}; shaders.set(canvas, current);
      function draw(now) {
        if (!canvas.isConnected) { stopShader(canvas); return; }
        canvas.width = Math.max(1, Math.round(canvas.clientWidth * Math.min(devicePixelRatio, 2)));
        canvas.height = Math.max(1, Math.round(canvas.clientHeight * Math.min(devicePixelRatio, 2)));
        gl.viewport(0, 0, canvas.width, canvas.height); gl.useProgram(program);
        gl.uniform1f(time, now / 1000); gl.uniform2f(resolution, canvas.width, canvas.height);
        gl.drawArrays(gl.TRIANGLES, 0, 6);
        current.frame = requestAnimationFrame(draw);
      }
      state.shader = {ok: true, source};
      current.frame = requestAnimationFrame(draw);
      return null;
    } catch (error) {
      if (vertex) gl.deleteShader(vertex); if (fragment) gl.deleteShader(fragment);
      if (program) gl.deleteProgram(program); if (buffer) gl.deleteBuffer(buffer);
      state.shader = {ok: false, error: String(error)};
      return 'Shader compilation failed: ' + error.message;
    }
  }
  function playAudio(frequency, level, cutoff, waveform) {
    stopAudio();
    try {
      const Context = window.AudioContext || window.webkitAudioContext;
      if (!Context) return 'Web Audio is unavailable in this browser.';
      audioContext ??= new Context();
      audioContext.resume().catch(error => { state.audio.error = String(error); stopAudio(); });
      const oscillator = audioContext.createOscillator(), gain = audioContext.createGain(), filter = audioContext.createBiquadFilter();
      oscillator.type = waveform; oscillator.frequency.value = frequency;
      gain.gain.setValueAtTime(0, audioContext.currentTime);
      gain.gain.linearRampToValueAtTime(Math.min(0.2, Math.max(0, level)), audioContext.currentTime + 0.03);
      gain.gain.setTargetAtTime(0, audioContext.currentTime + 1.75, 0.05);
      filter.type = 'lowpass'; filter.frequency.value = cutoff;
      oscillator.connect(gain); gain.connect(filter); filter.connect(audioContext.destination);
      voice = {oscillator, gain, filter}; oscillator.start();
      state.audio = {active: true, frequency, gain: level, cutoff, waveform};
      audioTimer = setTimeout(stopAudio, 2000);
      return null;
    } catch (error) { stopAudio(); return 'Audio could not start: ' + error.message; }
  }
  addEventListener('pagehide', stopAudio);
  document.addEventListener('visibilitychange', () => { if (document.hidden) stopAudio(); });
  window.saiGallery = {renderShader, stopShader, playAudio, stopAudio, state};
})();
