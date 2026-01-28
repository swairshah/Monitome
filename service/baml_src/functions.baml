// Functions for screenshot analysis

// Extract activity from a single screenshot
function ExtractScreenActivity(screenshot: image, timestamp: string) -> ScreenActivity {
  client Gemini
  prompt #"
    Analyze this screenshot and extract information about what the user is doing.

    Screenshot timestamp: {{ timestamp }}

    {{ screenshot }}

    Extract:
    1. What application is active
    2. What the user appears to be doing
    3. Any important text, URLs, or content visible

    Be concise but accurate.

    {{ ctx.output_format }}
  "#
}

// Summarize multiple screen activities
function SummarizeActivities(activities: ScreenActivity[]) -> ActivitySummary {
  client Gemini
  prompt #"
    Summarize the following screen activity data from {{ activities | length }} screenshots:

    {% for activity in activities %}
    ---
    Time: {{ activity.timestamp }}
    App: {{ activity.app.app_name }} ({{ activity.app.app_category }})
    Activity: {{ activity.activity_type }} - {{ activity.description }}
    Content: {{ activity.key_content | join(", ") }}
    {% endfor %}
    ---

    Provide a summary including:
    - Time period covered
    - Main activities
    - Apps used with counts
    - A productivity score (1-10)
    - A brief narrative summary

    {{ ctx.output_format }}
  "#
}

// Quick extraction - just get the basics
function QuickExtract(screenshot: image) -> AppContext {
  client Gemini
  prompt #"
    Quickly identify what app and window is shown in this screenshot.

    {{ screenshot }}

    {{ ctx.output_format }}
  "#
}
