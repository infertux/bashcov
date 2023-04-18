## Unreleased ([changes](https://github.com/infertux/bashcov/compare/v3.0.2...master))

  * TBD

## v3.0.2, 2023-04-18 ([changes](https://github.com/infertux/bashcov/compare/v3.0.1...v3.0.2))

  * [BUGFIX]  Match function names containing digits and colons

## v3.0.1, 2023-04-15 ([changes](https://github.com/infertux/bashcov/compare/v3.0.0...v3.0.1))

  * [BUGFIX]  Fix incorrect executables path in gemspec

## v3.0.0, 2023-04-10 ([changes](https://github.com/infertux/bashcov/compare/v1.8.2...v3.0.0))

  * [MISC]    New minimum Bash version supported is 4.3
  * [MISC]    New minimum Ruby version supported is 3.0
  * [BUGFIX]  Running Bashcov as root is now working (especially useful with Docker) although it is not recommended (#31, #43 and #56)
  * [BUGFIX]  Fix comments preceded by tabs not filtered out (#68)
  * [BUGFIX]  Fix two-line multilines not being treated as related (#67)
  * [BUGFIX]  Redefine `BASH_VERSION` when `bash_path` is read from command options (#57)
  * [BUGFIX]  Mute output from Bashcov and SimpleCov when requested (#54)
  * [BUGFIX]  Correctly handle empty scripts by short-circuiting
              `FieldStream#each` if the reader stream is at end-of-file before
              the start-of-fields pattern is encountered (#41)
  * [FEATURE] Bashcov omits from the coverage results any files that match one
              or more of the filters in `SimpleCov.filters` (#38)
  * [FEATURE] Ensure that files matching the `SimpleCov.tracked_files` glob
              pattern are included in the coverage results, regardless of
              whether `Bashcov.skip_uncovered` is enabled (#38)

## v1.8.2, 2018-03-27 ([changes](https://github.com/infertux/bashcov/compare/v1.8.1...v1.8.2))

  * [BUGFIX]  Fix coverage for complex heredoc constructions (#32)

## v1.8.1, 2018-03-01 ([changes](https://github.com/infertux/bashcov/compare/v1.8.0...v1.8.1))

  * [BUGFIX]  Fix incorrect coverage for some multiline strings (#35)

## v1.8.0, 2018-01-13 ([changes](https://github.com/infertux/bashcov/compare/v1.7.0...v1.8.0))

  * [FEATURE] Merge coverage results from multiple runs when
              `SimpleCov.use_merging` is set to `true`. Auto-generate
              likely-unique values for `SimpleCov.command_name`, providing the
              `--command-name` option and `BASHCOV_COMMAND_NAME` environment
              variable for users to set a command name explicitly (#34)

## v1.7.0, 2017-12-28 ([changes](https://github.com/infertux/bashcov/compare/v1.6.0...v1.7.0))

  * [MISC]    Add support for Ruby 2.5 and drop 2.2
  * [BUGFIX]  Fix issue where coverage would be run twice and overwritten (#33)
  * [FEATURE] Enhance shell script detection by parsing shebangs, checking
              filename extensions, and running syntax checks with `bash -n`
              (classes `Detective` & `Runner`) (#30)

## v1.6.0, 2017-10-24 ([changes](https://github.com/infertux/bashcov/compare/v1.5.1...v1.6.0))

  * [BUGFIX]  Don't crash when files contain invalid UTF-8 characters (#27)
  * [FEATURE] Upgrade SimpleCov dependency to 0.15

## v1.5.1, 2017-03-10 ([changes](https://github.com/infertux/bashcov/compare/v1.5.0...v1.5.1))

  * [BUGFIX]  Fix incorrect coverage for some multiline strings (#26)

## v1.5.0, 2017-02-08 ([changes](https://github.com/infertux/bashcov/compare/v1.4.1...v1.5.0))

  * [BUGFIX]  Fix incorrect coverage for some multiline strings (#23)
  * [FEATURE] Add support for Ruby 2.4

## v1.4.1, 2016-10-11 ([changes](https://github.com/infertux/bashcov/compare/v1.4.0...v1.4.1))

  * [BUGFIX]  Fix incorrect coverage for some multiline strings (#22)

## v1.4.0, 2016-10-08 ([changes](https://github.com/infertux/bashcov/compare/v1.3.1...v1.4.0))

  * [BUGFIX]  Fix incorrect coverage for case statements (#21)
  * [BUGFIX]  Fix rare race condition leading to a crash when a file is deleted at the wrong moment
  * [FEATURE] Add support for heredoc and multiline strings in general (#2)
  * [MISC]    Set up Travis CI to test Bashcov with Bash 4.0 through 4.4
  * [MISC]    Drop support for old Ruby versions (2.0 and 2.1)

## v1.3.1, 2016-02-19 ([changes](https://github.com/infertux/bashcov/compare/v1.3.0...v1.3.1))

  * [FEATURE] Add support back for Ruby 2.0.0 until it's officially EOL
  * [BUGFIX]  Expand `PS4` variables to empty strings so that Bashcov won't cause scripts to abort when Bash is running under `set -o nounset`

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

  * [BUGFIX]  Preserve original exit status when exiting Bashcov

## v1.2.0, 2015-05-04 ([changes](https://github.com/infertux/bashcov/compare/v1.1.0...v1.2.0))

  * [FEATURE] Enforce coherent coding style with Rubocop
  * [FEATURE] Upgrade dependencies (#11)
  * [FEATURE] Improve OS X compatibility (#10)

## v1.1.0, 2015-02-20 ([changes](https://github.com/infertux/bashcov/compare/v1.0.1...v1.1.0))

  * [FEATURE] Upgrade dependencies

## v1.0.1, 2013-03-21 ([changes](https://github.com/infertux/bashcov/compare/v1.0.0...v1.0.1))

  * [BUGFIX]  Allow to add SimpleCov filters
  * [BUGFIX]  Lines containing only `elif` should be ignored

## v1.0.0, 2013-03-16 ([changes](https://github.com/infertux/bashcov/compare/v0.0.9...v1.0.0))

  * First stable release. Enjoy!

## v0.0.1 to v0.0.9, 2012-12-08 to 2013-03-05 ([changes](https://github.com/infertux/bashcov/compare/v0.0.1...v0.0.9))

  * Experimental pre-releases. You should avoid to use these versions.

