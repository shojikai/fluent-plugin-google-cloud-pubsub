# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-google-cloud-pubsub"
  spec.version       = "0.0.1"
  spec.authors       = ["Shoji Kai"]
  spec.email         = ["sho2kai@gmail.com"]

  spec.summary       = %q{Fluentd plugin for Google Cloud Pub/Sub.}
  spec.description   = %q{Fluentd plugin for Google Cloud Pub/Sub.}

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.9"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_runtime_dependency "fluentd"
end
