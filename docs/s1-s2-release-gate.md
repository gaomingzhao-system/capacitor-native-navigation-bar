# S1 / S2 release gate

The pull request for this branch is created only after the dedicated branch gate completes successfully on the final serialized commit.

Required jobs:

1. Web lint, type checking, tests, ESM package build, `publint`, and `attw`
2. Swift Package build and Swift unit tests
3. CocoaPods lint
4. Android Gradle build, lint, and JVM tests using Java 21
5. Android API 30 instrumentation tests

The gate also verifies that temporary transformation workflows and scripts are absent from the deliverable.
