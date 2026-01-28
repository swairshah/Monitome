// LLM Client Configuration
client<llm> Gemini {
  provider google-ai
  options {
    model "gemini-2.5-pro"
    api_key env.GEMINI_API_KEY
  }
}

client<llm> GeminiFlash {
  provider google-ai
  options {
    model "gemini-2.5-flash-lite"
    api_key env.GEMINI_API_KEY
  }
}
