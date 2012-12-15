# Bashcov [![Build Status](https://secure.travis-ci.org/infertux/bashcov.png?branch=master)](https://travis-ci.org/infertux/bashcov) [![Code Climate](https://codeclimate.com/badge.png)](https://codeclimate.com/github/infertux/bashcov)

[bashcov] is [simplecov] for Bash.

Check out the **[demo](http://infertux.github.com/bashcov/test_app/)** - it's worth a thousand words.

## Installation

`$ gem install bashcov`

## Usage

`bashcov ./test_suite.sh`

This will create a directory named `coverage/` containing HTML files.

## Rationale

I'm a big fan of both Ruby's _simplecov_ and Bash.
_bashcov_ is my dream to have in Bash what _simplecov_ is to Ruby :).

Oddly enough, I didn't find any coverage tool for Bash except [shcov] but as stated [there](http://stackoverflow.com/questions/7188081/code-coverage-tools-for-validating-the-scripts), _shcov_ is:

> somewhat simplistic and doesn't handle all possible cases very well (especially when we're talking about long and complex lines)

Indeed, it doesn't work very well for me.
I have covered lines marked as uncovered and some files completely missed although executed through another script.

_bashcov_ aims to be a neat and working coverage tool backed by _simplecov_ and [simplecov-html].

## How does it work?

Ruby has a [coverage module](http://www.ruby-doc.org/stdlib-1.9.3/libdoc/coverage/rdoc/Coverage.html) which computes the coverage on demand.
Unfortunately, Bash doesn't have such niceties but we can use the [xtrace feature](http://www.gnu.org/software/bash/manual/bashref.html#index-BASH_005fXTRACEFD-178) which prints every line executed using [PS4](http://www.gnu.org/software/bash/manual/bashref.html#index-PS4).

After a bit of parsing, it sends results through _simplecov_ which generates an awesome HTML report.

And of course, you can take the most of _simplecov_ by adding a `.simplecov` file in your project's root (like [this](https://github.com/infertux/bashcov/blob/master/spec/test_app/.simplecov)).

## Todo

- YARD doc
- semver
- see if we could implement some features of Gcov

## License

MIT


[bashcov]: https://github.com/infertux/bashcov
[simplecov]: https://github.com/colszowka/simplecov
[simplecov-html]: https://github.com/colszowka/simplecov-html
[shcov]: http://code.google.com/p/shcov/source/browse/trunk/scripts/shcov

