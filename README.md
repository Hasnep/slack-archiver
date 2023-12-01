# Slack Archiver

A tool to scan files containing Slack links, then archive the conversations in those links to a GitHub repository and replace the Slack links with links to the archives.

## Setup

### GitHub Token

- [Generate a GitHub token](https://github.com/settings/tokens), select "classic token" and tick the "repo" scope, then generate the token.
- Copy the token and paste into a `.env` file, with the name `GITHUB_TOKEN=...`

### Slack Token

- [Create a new Slack app](https://api.slack.com/apps) and choose "from an app manifest".
- After choosing the workspace, copy and paste the contents of `./app-manifest.json`
- Open your Slack app's basic information page, and press "Install your app", then allow the app to access information.
- Select "OAuth & Permissions" from the app's sidebar and copy the User OAuth token for your workspace, paste it into a `.env` file with the name `SLACK_TOKEN=...`

### Configuration

Configuration is specified in a `config.toml` file, the fields are:

- `github_username` - the owner of the repo being used for archiving
- `github_repo_name` - the name of the repo being used for archiving
- `git_name` - the name that will be associated with the git commits
- `git_email` - the email that will be associated with the git commits
- `slack_workspace` - the name of your Slack workspace, e.g. `julialang`
- `github_token_environment_variable` and `slack_token_environment_variable` - optional, the names of the environment variables that will be checked for your tokens, default to `GITHUB_TOKEN` and `SLACK_TOKEN` respectively

## Running

Install the project's dependencies:

```shell
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

Then run the `src/SlackArchiver.jl` file, passing the paths to files containing Slack links that you want archived.
The files will automatically be overwritten with ones containing the new archived links.

```shell
julia --project=. src/SlackArchiver.jl ./path-to/my-file.md ./path-to/another-file.md
```

```julia
using SlackArchiver
SlackArchiver.archive(
    "path/to/config.toml", 
    ["./path-to/my-file.md", "./path-to/another-file.md"]
)
```
