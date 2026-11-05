# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "echarts" # @6.1.0 (vendored dist/echarts.esm.min.js directly -- the package's ESM entrypoint
# pulls in dozens of granular zrender/lib/* submodule specifiers that
# `./bin/importmap pin echarts` cannot resolve; see plan spike notes)
pin_all_from "app/javascript/controllers", under: "controllers"
