# Flutter vs React Native

## Context

Harmony is a music app. V1 needs reliable tanpura playback, while future versions may include a tuner, metronome, pitch detection, and other music tools.

The framework needs to support:

* Custom music-focused interfaces
* Reliable audio playback
* Future audio features
* Android and iOS
* Native capabilities when needed

## Flutter

### Pros

* **Better control over custom UI**

  * Useful for building instrument-like controls, animations, and visual interactions.

* **Consistent UI across platforms**

  * The same interface can behave and look consistently on Android and iOS.

* **Good native integration**

  * We can use native iOS and Android capabilities when the app needs more advanced audio functionality.

* **Good fit for Harmony's future**

  * The same foundation can support the Shruti app now and tools like tuner and pitch detection later.

### Cons

* Some advanced audio features may require native code.
* We need to carefully evaluate audio libraries before depending on them.

## React Native

### Pros

* **TypeScript support**

  * Works well with an existing React and TypeScript workflow.

* **Large ecosystem**

  * Many libraries and integrations are available.

* **Native integration**

  * Native iOS and Android functionality can be added when required.

### Cons

* **Less control over highly custom interfaces**

  * Harmony is closer to a musical instrument than a typical app, so custom interaction and rendering are important.

* **Advanced audio still requires native work**

  * React Native does not remove the need for native audio functionality.

* **More reliance on third-party libraries**

  * Important audio features may depend on external packages.

## Decision

**Harmony will use Flutter.**

Flutter is the better fit because:

1. Harmony needs a highly custom interface.
2. Consistent Android and iOS UI is important.
3. We need a clear path to advanced audio features.
4. The architecture can grow from a Shruti app into a broader music toolkit.

### Architecture

Keep the UI and audio separate:

```text
Flutter UI
    ↓
Audio Service
    ↓
Native Audio
```

This lets us start simple with tanpura playback without limiting future audio features.

**Decision: Flutter**
