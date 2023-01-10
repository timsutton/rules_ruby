load("//ruby/private:library.bzl", LIBRARY_ATTRS = "ATTRS")
load("//ruby/private:providers.bzl", "RubyFiles", "get_transitive_data", "get_transitive_srcs")

def _rb_gem_build_impl(ctx):
    gem_builder = ctx.actions.declare_file("{}_gem_builder.rb".format(ctx.label.name))
    transitive_data = get_transitive_data(ctx.files.data, ctx.attr.deps).to_list()
    transitive_srcs = get_transitive_srcs(ctx.files.srcs, ctx.attr.deps).to_list()
    toolchain = ctx.toolchains["@rules_ruby//ruby:toolchain_type"]

    # Inputs manifest is a dictionary where:
    #   - key is a path where a file is available (https://bazel.build/rules/lib/File#path)
    #   - value is a path where a file should be (https://bazel.build/rules/lib/File#short_path)
    # They are the same for source inputs, but different for generated ones.
    # We need to make sure that gem builder script copies both correctly, e.g.:
    #   {
    #     "rb/Gemfile": "rb/Gemfile",
    #     "bazel-out/darwin_arm64-fastbuild/bin/rb/LICENSE": "rb/LICENSE",
    #   }
    inputs = transitive_data + transitive_srcs + [gem_builder]
    inputs_manifest = {}
    for src in inputs:
        inputs_manifest[src.path] = src.short_path

    ctx.actions.expand_template(
        template = ctx.file._gem_builder_tpl,
        output = gem_builder,
        substitutions = {
            "{bazel_out_dir}": ctx.outputs.gem.dirname,
            "{gem_filename}": ctx.outputs.gem.basename,
            "{gemspec}": ctx.file.gemspec.path,
            "{inputs_manifest}": json.encode(inputs_manifest),
        },
    )

    args = ctx.actions.args()
    args.add(gem_builder)
    ctx.actions.run(
        inputs = depset(inputs),
        executable = toolchain.ruby,
        arguments = [args],
        outputs = [ctx.outputs.gem],
        use_default_shell_env = True,
    )

    return [
        RubyFiles(
            transitive_data = depset(transitive_data),
            transitive_srcs = depset(transitive_srcs),
        ),
    ]

rb_gem_build = rule(
    _rb_gem_build_impl,
    attrs = dict(
        LIBRARY_ATTRS,
        gemspec = attr.label(
            allow_single_file = [".gemspec"],
            mandatory = True,
            doc = "Gemspec file to use for gem building.",
        ),
        _gem_builder_tpl = attr.label(
            allow_single_file = True,
            default = "@rules_ruby//ruby/private:gem_build/gem_builder.rb.tpl",
        ),
    ),
    outputs = {
        "gem": "%{name}.gem",
    },
    toolchains = ["@rules_ruby//ruby:toolchain_type"],
    doc = """
Builds a Ruby gem.

Suppose you have the following Ruby gem, where `rb_library()` is used
in `BUILD` files to define the packages for the gem.

```output
|-- BUILD
|-- Gemfile
|-- WORKSPACE
|-- gem.gemspec
`-- lib
    |-- BUILD
    |-- gem
    |   |-- BUILD
    |   |-- add.rb
    |   |-- subtract.rb
    |   `-- version.rb
    `-- gem.rb
```

And a RubyGem specification is:

`gem.gemspec`:
```ruby
root = File.expand_path(__dir__)
$LOAD_PATH.push(File.expand_path('lib', root))
require 'gem/version'

Gem::Specification.new do |s|
  s.name = 'example'
  s.version = GEM::VERSION

  s.authors = ['Foo Bar']
  s.email = ['foobar@gmail.com']
  s.homepage = 'http://rubygems.org'
  s.license = 'MIT'

  s.summary = 'Example'
  s.description = 'Example gem'
  s.files = ['Gemfile'] + Dir['lib/**/*']

  s.require_paths = ['lib']
  s.add_dependency 'rake', '~> 10'
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'rubocop', '~> 1.10'
end
```

You can now package everything into a `.gem` file by defining a target:

`BUILD`:
```bazel
load("@rules_ruby//ruby:defs.bzl", "rb_gem_build", "rb_library")

package(default_visibility = ["//:__subpackages__"])

rb_library(
    name = "gem",
    srcs = [
        "Gemfile",
        "Gemfile.lock",
        "gem.gemspec",
    ],
    deps = ["//lib:gem"],
)

rb_gem_build(
    name = "gem-build",
    gemspec = "gem.gemspec",
    deps = [":gem"],
)
```

```output
$ bazel build :gem-build
INFO: Analyzed target //:gem-build (0 packages loaded, 0 targets configured).
INFO: Found 1 target...
INFO: From Action gem-build.gem:
  Successfully built RubyGem
  Name: example
  Version: 0.1.0
  File: example-0.1.0.gem
Target //:gem-build up-to-date:
  bazel-bin/gem-build.gem
INFO: Elapsed time: 0.196s, Critical Path: 0.10s
INFO: 2 processes: 1 internal, 1 darwin-sandbox.
INFO: Build completed successfully, 2 total actions
```
    """,
)
