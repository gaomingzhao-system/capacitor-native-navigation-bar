# S1 / S2 validation matrix

This change set is accepted only after the branch gate verifies all of the following against the packed source tree:

- TypeScript formatting, lint, type checking, Vitest, ESM build, publint, and Are the Types Wrong
- Swift Package build and Swift unit tests
- CocoaPods specification lint
- Android library build, lint, and JVM tests with JDK 21
- Android API 30 instrumentation tests
- Removal of all one-shot transformation files before pull request creation

The regression suite covers transactional tabbar patches, listener-registration recovery, declarative reset/error behavior, bounded transition snapshots, SVG colors and elliptical arcs, native hierarchy restoration, Android start-side navbar actions, shared Liquid Glass source capture, and API 30 behavior.
