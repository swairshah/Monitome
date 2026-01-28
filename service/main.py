"""
Monitome Analysis Service

FastAPI service that uses BAML for screenshot analysis.
Run with: uvicorn main:app --port 8420
"""

import base64
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# Import generated BAML client
from baml_client import b
from baml_client.types import ScreenActivity, AppContext, ActivitySummary

app = FastAPI(
    title="Monitome Analysis Service",
    description="Screenshot analysis using BAML + Gemini",
    version="0.1.0",
)


# Request/Response models
class AnalyzeRequest(BaseModel):
    """Request to analyze a screenshot"""
    image_base64: str
    timestamp: str  # ISO format


class AnalyzeFileRequest(BaseModel):
    """Request to analyze a screenshot by file path"""
    file_path: str
    timestamp: str | None = None


class QuickExtractRequest(BaseModel):
    """Request for quick app extraction"""
    image_base64: str


class SummarizeRequest(BaseModel):
    """Request to summarize activities"""
    activities: list[dict]


# Health check
@app.get("/health")
async def health():
    return {"status": "ok", "service": "monitome-analysis"}


# Analyze screenshot from base64
@app.post("/analyze", response_model=dict)
async def analyze_screenshot(request: AnalyzeRequest):
    """Analyze a screenshot and extract activity information"""
    try:
        from baml_py import Image

        image = Image.from_base64("image/png", request.image_base64)
        result: ScreenActivity = await b.ExtractScreenActivity(
            screenshot=image,
            timestamp=request.timestamp
        )
        return result.model_dump()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Analyze screenshot from file path
@app.post("/analyze-file", response_model=dict)
async def analyze_file(request: AnalyzeFileRequest):
    """Analyze a screenshot from a file path"""
    try:
        from baml_py import Image

        path = Path(request.file_path)
        if not path.exists():
            raise HTTPException(status_code=404, detail=f"File not found: {request.file_path}")

        image_data = path.read_bytes()
        image_b64 = base64.b64encode(image_data).decode()

        # Determine media type
        suffix = path.suffix.lower()
        media_type = {
            ".png": "image/png",
            ".jpg": "image/jpeg",
            ".jpeg": "image/jpeg",
        }.get(suffix, "image/png")

        image = Image.from_base64(media_type, image_b64)
        timestamp = request.timestamp or datetime.now().isoformat()

        result: ScreenActivity = await b.ExtractScreenActivity(
            screenshot=image,
            timestamp=timestamp
        )
        return result.model_dump()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Quick extract - just get app info
@app.post("/quick-extract", response_model=dict)
async def quick_extract(request: QuickExtractRequest):
    """Quick extraction of app context only"""
    try:
        from baml_py import Image

        image = Image.from_base64("image/png", request.image_base64)
        result: AppContext = await b.QuickExtract(screenshot=image)
        return result.model_dump()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Summarize activities
@app.post("/summarize", response_model=dict)
async def summarize_activities(request: SummarizeRequest):
    """Summarize a list of screen activities"""
    try:
        # Convert dicts to ScreenActivity objects
        activities = [ScreenActivity(**a) for a in request.activities]
        result: ActivitySummary = await b.SummarizeActivities(activities=activities)
        return result.model_dump()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=8420)
