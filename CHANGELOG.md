## Unreleased ([changes](https://github.com/infertux/bashcov/compare/v1.3.0...master))

  * TBD

## v1.3.0, 2016-02-10 ([changes](https://github.com/infertux/bashcov/compare/v1.2.1...v1.3.0))

  * [FEATURE] Upgrade SimpleCov dependency to 0.11
  * [FEATURE] Add support for Ruby 2.3 and drop 1.9
  * [FEATURE] Add ability to pass `--bash-path` and `--root` as arguments
  * [FEATURE] Add basic support for Bash versions prior to 4.1 (no `BASH_XTRACEFD`)
  * [FEATURE] Handle `pushd` & `popd` commands
  * [BUGFIX]  Fix potential bug with long paths under Bash 4.2 as it truncates `PS4` to 128 characters
  * [BUGFIX]  Fail gracefully if a Bash script unsets `LINENO`
  * [BUGFIX]  Refactor parser to not use subshells in `PS4` as it causes erroneous extra hits as well as being slow (classes `FieldStream` & `Xtrace`)
              Big kudos to @BaxterStockman for his awesome work on PR #16
              See https://github.com/infertux/bashcov/#some-gory-details

## v1.2.1, 2015-05-05 ([changes](https://github.com/infertux/bashcov/compare/v1.2.0...v1.2.1))

  * [BUGFIX] Preserve original exit status when exiting Bashcov

## v1.2.0, 2015-05-04 ([changes](https://github.com/infertux/bashcov/compare/v1.1.0...v1.2.0))

  * [FEATURE] Enforce coherent coding style with Rubocop
  * [FEATURE] Upgrade dependencies (#11)
  * [FEATURE] Improve OS X compatibility (#10)

## v1.1.0, 2015-02-20 ([changes](https://github.com/infertux/bashcov/compare/v1.0.1...v1.1.0))

  * [FEATURE] Upgrade dependencies

## v1.0.1, 2013-03-21 ([changes](https://github.com/infertux/bashcov/compare/v1.0.0...v1.0.1))

  * [BUGFIX] Allow to add SimpleCov filters
  * [BUGFIX] Lines containing only `elif` should be ignored

## v1.0.0, 2013-03-16 ([changes](https://github.com/infertux/bashcov/compare/v0.0.9...v1.0.0))

  * First stable release. Enjoy!

## v0.0.1 to v0.0.9, 2012-12-08 to 2013-03-05 ([changes](https://github.com/infertux/bashcov/compare/v0.0.1...v0.0.9))

  * Experimental pre-releases. You should avoid to use these versions.

