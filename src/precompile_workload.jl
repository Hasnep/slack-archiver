using PrecompileTools: @setup_workload, @compile_workload

@setup_workload begin
    example_toml = """
    github_username = "my-github-username"
    github_repo_name = "slack-archive"
    git_name = "Slack Archiver"
    git_email = "slack-archiver@example.com"
    slack_workspace = "julialang"
    """
    @compile_workload begin
        config = parse_config(example_toml)
        # Put more stuff here
    end
end