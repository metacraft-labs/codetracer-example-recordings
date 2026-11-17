## Reprobuild project file for `codetracer-example-recordings`.
##
## Example CodeTracer recordings. Consumers (codetracer's test lanes) read a
## checkout at `../codetracer-example-recordings`.
##
## This recipe builds nothing and declares only its package: that is what
## lets a consumer name it in `uses:` (by its directory name,
## `"codetracer-example-recordings"`) and lets `repro lock refresh` pin it in
## the consumer's `repro.lock`, which is the one record of a repo's
## dependencies. It declares no `uses:` of its own.

import repro_project_dsl

package codetracer_example_recordings:
  defaultToolProvisioning "path"
