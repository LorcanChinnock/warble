# Changelog

## [0.1.0-beta.5](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.4...v0.1.0-beta.5) (2026-10-20)


### Features

* **app:** menu bar icon from the app icon's bars ([#85](https://github.com/LorcanChinnock/warble/issues/85)) ([98b5ee0](https://github.com/LorcanChinnock/warble/commit/98b5ee0aee26a692c53e907e27478a6f01079276))
* **displays:** virtual notch on external displays and Macs without a notch ([#94](https://github.com/LorcanChinnock/warble/issues/94)) ([7f0845b](https://github.com/LorcanChinnock/warble/commit/7f0845b4322b603f4aaee05210978811cdfd4086))
* **doctor:** explain why nothing is detected ([#95](https://github.com/LorcanChinnock/warble/issues/95)) ([5821369](https://github.com/LorcanChinnock/warble/commit/58213699e5713a5dccce2633ea0b7b84644f6a4a))
* **model:** return to idle a while after pausing ([#98](https://github.com/LorcanChinnock/warble/issues/98)) ([9d429df](https://github.com/LorcanChinnock/warble/commit/9d429dfe872bc4c72f1456a01126598d91d823b1)), closes [#91](https://github.com/LorcanChinnock/warble/issues/91)
* **model:** source priority and ignore list ([#69](https://github.com/LorcanChinnock/warble/issues/69)) ([01dcee0](https://github.com/LorcanChinnock/warble/commit/01dcee0120d50fd92e110fbfd9f8389f66f0abf9))
* **model:** toast queue ([#68](https://github.com/LorcanChinnock/warble/issues/68)) ([fbced5a](https://github.com/LorcanChinnock/warble/commit/fbced5a92d297680022f8ed5e85e04abab2269e0))
* **notch:** animate between idle and playing ([#101](https://github.com/LorcanChinnock/warble/issues/101)) ([5c656bc](https://github.com/LorcanChinnock/warble/commit/5c656bc749ebedcc72722d97fc1843f8d8a2e46f))
* **notch:** reveal an idle card on hover when nothing is playing ([#99](https://github.com/LorcanChinnock/warble/issues/99)) ([29e924b](https://github.com/LorcanChinnock/warble/commit/29e924bc67cc0f1002ab75180c592330452bd93e))


### Bug Fixes

* **notch:** match the camera housing exactly on every MacBook ([#97](https://github.com/LorcanChinnock/warble/issues/97)) ([28b7d1a](https://github.com/LorcanChinnock/warble/commit/28b7d1ab687ec6d315f381975ed7a33f32df1580))
* **now-playing:** stop the adapter when Warble is killed ([#88](https://github.com/LorcanChinnock/warble/issues/88)) ([a2a8a20](https://github.com/LorcanChinnock/warble/commit/a2a8a203e1cc689b3fabaf81a6b18b8b0a849c77))

## [0.1.0-beta.4](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.3...v0.1.0-beta.4) (2026-10-19)


### Features

* **notch:** album-art glow and fallback gradient ([#82](https://github.com/LorcanChinnock/warble/issues/82)) ([795f176](https://github.com/LorcanChinnock/warble/commit/795f176b584d4620d4d71388f3750814d892009a))
* **notch:** art and play-state bars in the resting wings ([#81](https://github.com/LorcanChinnock/warble/issues/81)) ([9b4789f](https://github.com/LorcanChinnock/warble/commit/9b4789f5163491fa5b21bf94e0abad835d9a62e7))
* **notch:** hover opens the full card in one step ([#80](https://github.com/LorcanChinnock/warble/issues/80)) ([1ff16a8](https://github.com/LorcanChinnock/warble/commit/1ff16a8f04f343f7211e5cfdb4b39f8297e13b39))
* **now-playing:** AppleScript fallback for Spotify and Music ([#72](https://github.com/LorcanChinnock/warble/issues/72)) ([df7a631](https://github.com/LorcanChinnock/warble/commit/df7a63190cd0736ba318897fc4fc55c02f166026))
* **now-playing:** read and control playback through the adapter ([#67](https://github.com/LorcanChinnock/warble/issues/67)) ([4ebb095](https://github.com/LorcanChinnock/warble/commit/4ebb0958bce73e847c79ab7f15f4e81e89b73607))
* **outputs:** output device picker ([#83](https://github.com/LorcanChinnock/warble/issues/83)) ([f0c0ec7](https://github.com/LorcanChinnock/warble/commit/f0c0ec78cdbd5b33b73d07a4e13eb5bd220fdd7f))
* **player:** playback controls in the expanded notch ([#70](https://github.com/LorcanChinnock/warble/issues/70)) ([1c05202](https://github.com/LorcanChinnock/warble/commit/1c05202ce0546583173f20e378f06be83e5ee407))
* **player:** volume slider, and scroll on the notch for volume ([#71](https://github.com/LorcanChinnock/warble/issues/71)) ([f4a00b9](https://github.com/LorcanChinnock/warble/commit/f4a00b9e7420d1965036c24b0afa0fdb7295ac97))


### Bug Fixes

* **now-playing:** no error log for Music tracks without artwork ([#79](https://github.com/LorcanChinnock/warble/issues/79)) ([2e00b09](https://github.com/LorcanChinnock/warble/commit/2e00b097f09703a6f47f0c7a86eab07187b48db8))

## [0.1.0-beta.3](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.2...v0.1.0-beta.3) (2026-10-18)


### Features

* **model:** hover intent state machine ([#63](https://github.com/LorcanChinnock/warble/issues/63)) ([64341f8](https://github.com/LorcanChinnock/warble/commit/64341f8d8d1e382a90677825a74df61d60270141))
* **notch:** Peek and Expanded states with a shape morph ([#65](https://github.com/LorcanChinnock/warble/issues/65)) ([b63d36d](https://github.com/LorcanChinnock/warble/commit/b63d36d660dced91f3165d28b5c1d4e5929efca8))

## [0.1.0-beta.2](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.1...v0.1.0-beta.2) (2026-10-18)


### Features

* **model:** playback state with elapsed-time interpolation ([#61](https://github.com/LorcanChinnock/warble/issues/61)) ([bc9195a](https://github.com/LorcanChinnock/warble/commit/bc9195a790cad9701b472917a508a203568c1c3e))

## [0.1.0-beta.1](https://github.com/LorcanChinnock/warble/compare/v0.1.0-beta.0...v0.1.0-beta.1) (2026-10-18)


### Features

* **notch:** draw the notch panel in Hidden and Resting states ([#58](https://github.com/LorcanChinnock/warble/issues/58)) ([7d77cd9](https://github.com/LorcanChinnock/warble/commit/7d77cd9bf24b4d81aa151191f11ac87587e80656))

## Changelog
