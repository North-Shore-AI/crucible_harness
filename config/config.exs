import Config

config :crucible_harness,
  ecto_repos: [CrucibleFramework.Repo]

config :crucible_framework,
  enable_repo: true

import_config "#{config_env()}.exs"
