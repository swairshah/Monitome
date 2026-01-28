// Types for screenshot analysis

// What application is visible in the screenshot
class AppContext {
  app_name string @description("Name of the active application")
  window_title string? @description("Title of the active window if visible")
  app_category AppCategory @description("Category of the application")
}

enum AppCategory {
  Browser
  IDE
  Terminal
  Communication @alias("chat, email, slack, etc")
  Media @alias("video, music, images")
  Productivity @alias("documents, spreadsheets, notes")
  System @alias("settings, finder, file manager")
  Other
}

// Activity detected in the screenshot
class ScreenActivity {
  timestamp string @description("ISO timestamp of the screenshot")
  app AppContext
  activity_type ActivityType
  description string @description("Brief description of what user is doing")
  key_content string[] @description("Important text or content visible")
  urls string[] @description("Any URLs visible in the screenshot")
}

enum ActivityType {
  Coding
  Reading
  Writing
  Browsing
  Communicating
  Watching
  Idle
  Unknown
}

// Summary of multiple screenshots
class ActivitySummary {
  time_period string @description("Time period covered, e.g. '2pm-4pm'")
  total_screenshots int
  main_activities string[] @description("Top activities during this period")
  apps_used AppUsage[] @description("Apps used with approximate time")
  productivity_score int @description("1-10 score of productivity")
  summary string @description("2-3 sentence summary of the session")
}

class AppUsage {
  app_name string
  category AppCategory
  screenshot_count int @description("Number of screenshots showing this app")
}
