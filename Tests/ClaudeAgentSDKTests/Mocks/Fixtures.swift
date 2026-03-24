import Foundation

/// JSON fixture strings from real Claude CLI output for testing.
enum Fixtures {
    static let systemInitMessage = """
    {"type":"system","subtype":"init","agents":[],"api_key_source":"oauth","betas":[],"claude_code_version":"2.1.81","cwd":"/Users/test","tools":["Bash","Read","Edit","Write","Glob","Grep"],"mcp_servers":[],"model":"claude-sonnet-4-6","permission_mode":"default","slash_commands":[],"output_style":"normal","skills":[],"plugins":[],"fast_mode_state":"off","uuid":"11111111-1111-1111-1111-111111111111","session_id":"session-123"}
    """

    static let assistantMessage = """
    {"type":"assistant","message":{"id":"msg_xxx","type":"message","role":"assistant","content":[{"type":"text","text":"Hello! How can I help you today?"}],"model":"claude-sonnet-4-6","stop_reason":"end_turn","usage":{"input_tokens":10,"output_tokens":12}},"parent_tool_use_id":null,"uuid":"22222222-2222-2222-2222-222222222222","session_id":"session-123"}
    """

    static let resultSuccess = """
    {"type":"result","subtype":"success","duration_ms":2712,"duration_api_ms":2683,"is_error":false,"num_turns":1,"result":"Hello! How can I help you today?","stop_reason":"end_turn","session_id":"session-123","total_cost_usd":0.049515,"usage":{"input_tokens":3,"cache_creation_input_tokens":7872,"cache_read_input_tokens":0,"output_tokens":12,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":7872}},"model_usage":{"claude-sonnet-4-6":{"input_tokens":3,"output_tokens":12,"cache_read_input_tokens":0,"cache_creation_input_tokens":7872,"web_search_requests":0,"cost_u_s_d":0.049515,"context_window":200000,"max_output_tokens":64000}},"permission_denials":[],"fast_mode_state":"off","uuid":"33333333-3333-3333-3333-333333333333"}
    """

    static let resultError = """
    {"type":"result","subtype":"error_max_turns","duration_ms":5000,"duration_api_ms":4500,"is_error":true,"num_turns":10,"stop_reason":null,"session_id":"session-123","total_cost_usd":1.5,"usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":500,"server_tool_use":null,"service_tier":"standard","cache_creation":null},"model_usage":{},"permission_denials":[],"errors":["Max turns reached"],"fast_mode_state":"off","uuid":"44444444-4444-4444-4444-444444444444"}
    """

    static let statusMessage = """
    {"type":"system","subtype":"status","status":"compacting","permission_mode":"default","uuid":"55555555-5555-5555-5555-555555555555","session_id":"session-123"}
    """

    static let toolProgressMessage = """
    {"type":"tool_progress","tool_use_id":"tu_123","tool_name":"Bash","parent_tool_use_id":null,"elapsed_time_seconds":2.5,"uuid":"66666666-6666-6666-6666-666666666666","session_id":"session-123"}
    """

    static let taskStartedMessage = """
    {"type":"system","subtype":"task_started","task_id":"task-1","tool_use_id":"tu_456","description":"Running tests","uuid":"77777777-7777-7777-7777-777777777777","session_id":"session-123"}
    """

    static let rateLimitEvent = """
    {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","utilization":0.5},"uuid":"88888888-8888-8888-8888-888888888888","session_id":"session-123"}
    """

    static let promptSuggestion = """
    {"type":"prompt_suggestion","suggestion":"Can you also add tests?","uuid":"99999999-9999-9999-9999-999999999999","session_id":"session-123"}
    """

    static let controlRequestPermission = """
    {"type":"control_request","request_id":"req-001","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"},"tool_use_id":"tu_789"}}
    """

    static let keepAlive = """
    {"type":"keep_alive"}
    """
}
