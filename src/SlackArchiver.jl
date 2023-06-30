module SlackArchiver

import HTTP
using Memoization
import Dates
import JSON3
using Base64
import TOML

# Config

function get_input_markdown_file_paths()
    return ARGS
end

function read_file(file_path)
    open(file_path) do f
        return read(f, String)
    end
end

function get_environment_variable(name)
    try
        return ENV[name]
    catch
        throw("Environment variable `$(name)` not set.")
    end
end

function parse_config(config_string)
    config = TOML.parse(config_string)
    return (
        github_token=get_environment_variable(
            get(config, "github_token_environment_variable", "GITHUB_TOKEN"),
        ),
        slack_token=get_environment_variable(
            get(config, "slack_token_environment_variable", "SLACK_TOKEN"),
        ),
        github_username=config["github_username"],
        github_repo_name=config["github_repo_name"],
        git_name=config["git_name"],
        git_email=config["git_email"],
        slack_workspace=config["slack_workspace"],
    )
end

## Slack

function get_slack_link_pattern(slack_workspace)
    return Regex("https:\\/\\/$(slack_workspace)\\.slack\\.com\\/archives\\/\\w+\\/\\w+")
end

function extract_slack_links(s; slack_workspace)
    return [m.match for m in eachmatch(get_slack_link_pattern(slack_workspace), s)]
end

function get_slack_api(method, query; config)
    url = "https://slack.com/api/$method"
    response = HTTP.get(
        url,
        query=query,
        headers=Dict("Authorization" => "Bearer $(config.slack_token)"),
    )
    return JSON3.read(response.body)
end

function get_message_from_link(slack_link; config)
    @info "Getting message at link `$slack_link`."
    search_result = get_slack_api("search.messages", Dict(:query => slack_link); config)
    # Assume the first match is the message we are looking for
    message = first(search_result[:messages][:matches])
    return (channel_id=message[:channel][:id], timestamp_str=message[:ts])
end

# Memoise this function because we will probably need to look up the same user multiple times
@memoize function get_user_info(user_id; config)
    @info "Getting info for user `$user_id`."
    user_result = get_slack_api("users.info", Dict(:user => user_id); config)
    return (username=user_result[:user].name, real_name=user_result[:user].real_name)
end

function get_thread_messages(channel_id, timestamp_str; config)
    @info "Getting thread messages for channel `$channel_id` and timestamp `$timestamp_str`."
    replies_result = get_slack_api(
        "conversations.replies",
        Dict(:channel => channel_id, :ts => timestamp_str);
        config
    )
    return [
        (
            timestamp=parse(Float64, message[:ts]),
            user=get_user_info(message[:user]; config),
            text=message[:text],
        ) for message in replies_result[:messages]
    ]
end

function get_thread_from_link(slack_link; config)
    (channel_id, timestamp_str) = get_message_from_link(slack_link; config)
    messages = get_thread_messages(channel_id, timestamp_str; config)
    return (
        channel_id=channel_id,
        thread_id=replace(timestamp_str, "." => ""),
        messages=messages,
    )
end

# Serialise threads

function markdown_quote(s)
    lines = split(s, "\n")
    return join(["> $(line)" for line in lines], "\n")
end

function markdown_bold(s)
    return "**$(s)**"
end

function markdown_italic(s)
    return "_$(s)_"
end

function serialise_timestamp(timestamp)
    return Dates.format(Dates.unix2datetime(timestamp), "yyyy-mm-dd HH:MM:SS")
end

function serialise_message(message)
    return join(
        [
            markdown_bold(message.user.real_name),
            " ",
            "(",
            message.user.username,
            ")",
            " ",
            markdown_italic(serialise_timestamp(message.timestamp)),
            "\n\n",
            markdown_quote(message.text),
        ],
        "",
    )
end

function serialise_thread(thread)
    return join([serialise_message(message) for message in thread.messages], "\n\n---\n\n")
end

# GitHub

function get_thread_markdown_path(thread)
    return thread.channel_id * "/" * thread.thread_id * ".md"
end

function upload_file_to_github(contents, file_path; config)
    url = "https://api.github.com/repos/$(config.github_username)/$(config.github_repo_name)/contents/$file_path"
    headers = Dict(
        "Accept" => "application/vnd.github+json",
        "Authorization" => "token $(config.github_token)",
        "X-GitHub-Api-Version" => "2022-11-28",
    )

    # Check if the file already exists
    local contents_response
    try
        @info "Checking if the file `$file_path` already exists."
        contents_response = HTTP.get(url; headers)
    catch
        # The file doesn't exist
        (existing_file_sha, existing_file_contents) = (nothing, nothing)
    else
        # The file does exist, so we need its sha to update it and the current contents to compare with
        existing_file = JSON3.read(contents_response.body)
        existing_file_sha = existing_file.sha
        existing_file_contents = String(base64decode(existing_file[:content]))
    end

    if contents == existing_file_contents
        @info "The file `$file_path` is already up to date."
    else
        body = Dict(
            :message =>
                isnothing(existing_file_contents) ? "Add $(file_path)" :
                "Update $(file_path)",
            :committer => Dict(:name => config.git_name, :email => config.git_email),
            :content => Base64.base64encode(contents),
            :sha => existing_file_sha,
        )
        @info "Uploading file to `$file_path`."
        _upload_response = HTTP.put(url; headers, body=JSON3.write(body))
    end

    # Get the URL where the uploaded file will be accessible
    return "https://github.com/$(config.github_username)/$(config.github_repo_name)/blob/main/$file_path"
end

# Main function

function archive(config_path)
    config = parse_config(read_file(config_path))

    markdown_file_paths = get_input_markdown_file_paths()
    for markdown_file_path in markdown_file_paths
        markdown_file_contents = read_file(markdown_file_path)
        slack_links = extract_slack_links(markdown_file_contents; config.slack_workspace)
        for slack_link in slack_links
            thread = get_thread_from_link(slack_link; config)
            thread_serialised = serialise_thread(thread)
            thread_path = get_thread_markdown_path(thread)
            thread_github_url =
                upload_file_to_github(thread_serialised, thread_path; config)
            markdown_file_contents =
                replace(markdown_file_contents, slack_link => thread_github_url)
        end
        @info "Updating markdown file `$markdown_file_path`."
        write(markdown_file_path, markdown_file_contents)
    end
end

end # module