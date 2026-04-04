import os
import av
import torch
import numpy as np

# Patch av backend vào VIDEO_READER_BACKENDS trước khi dùng
from qwen_vl_utils import vision_process

def _read_video_av(ele):
    video_path = ele["video"]
    fps_requested = ele.get("fps", 1.0)
    max_frames = ele.get("max_frames", 64)

    frames = []
    with av.open(video_path) as container:
        stream = container.streams.video[0]
        video_fps = float(stream.average_rate)
        step = max(1, int(video_fps / fps_requested))

        for i, frame in enumerate(container.decode(video=0)):
            if i % step == 0:
                img = frame.to_ndarray(format="rgb24")
                frames.append(img)
            if len(frames) >= max_frames:
                break

    video_tensor = torch.from_numpy(np.stack(frames))  # (T, H, W, C)
    metadata = {"video_fps": video_fps}
    sample_fps = fps_requested
    return video_tensor, metadata, sample_fps

# Inject vào dict của qwen_vl_utils
vision_process.VIDEO_READER_BACKENDS["av"] = _read_video_av
os.environ["FORCE_QWENVL_VIDEO_READER"] = "av"

from transformers import Qwen3VLForConditionalGeneration, AutoProcessor
from qwen_vl_utils import process_vision_info

model = Qwen3VLForConditionalGeneration.from_pretrained(
    "Qwen/Qwen3-VL-2B-Instruct",
    torch_dtype=torch.float16,
    device_map="auto",
    attn_implementation="eager"
)
processor = AutoProcessor.from_pretrained("Qwen/Qwen3-VL-4B-Instruct-FP8")

messages = [
    {
        "role": "user",
        "content": [
            {
                "type": "video",
                "video": "/Users/nguyenvantoan/Documents/git/veea-context-capture/backend/data/7684774729217.mp4",
                "fps": 1.0,
                "max_pixels": 360 * 420,
                "max_frames": 64,
                "video_fps": 1.0
            },
            {
                "type": "text",
                "text": """
                You are a Digital Data Archiving Specialist specializing in Image Data Extraction from screen recordings.

                Your task is to analyze a screen recording and convert observable user actions into a structured JSON report.

                ========================
                STRICT RULES
                ========================

                1. OUTPUT FORMAT
                - Return ONLY a valid JSON object.
                - Do NOT include explanations, markdown, comments, or extra text.

                2. EVIDENCE-BASED EXTRACTION
                - Only extract tasks, commitments, or appointments when there is CLEAR CONFIRMATION evidence, such as:
                - The user clicks "Confirm", "Submit", "Save"
                - The user types or selects phrases like: "Done", "OK", "Booked", "Confirmed", "See you then"
                - If there is no explicit confirmation → DO NOT include it.

                3. NO HALLUCINATION
                - Do NOT infer missing details.
                - If data is unclear or partially visible → use null.
                - If nothing qualifies → return empty arrays [].

                4. NO TIMESTAMPS
                - Do NOT include timestamps from the video.
                - Use semantic descriptions instead (e.g., app name, action type).

                5. CONTEXT AWARENESS
                - Identify applications (e.g., Gmail, Calendar, Slack, Notion, Browser).
                - Track user intent across multiple steps ONLY if final confirmation exists.

                6. TO-DO DEFINITION
                - Include ONLY:
                - Tasks assigned TO the user
                - Tasks the user explicitly ACCEPTED or CONFIRMED
                - Exclude:
                - Suggestions
                - Draft messages
                - Unconfirmed actions

                ========================
                OUTPUT SCHEMA
                ========================

                {
                "activity_summary": "Concise summary of apps used and key actions performed",

                "To-Do List": [
                    {
                    "task": "string",
                    "source": "string (e.g., Slack, Email, Calendar)",
                    "evidence": "string (explicit confirmation action observed)"
                    }
                ],

                "behavioral_insight": "Professional analysis of user focus, workflow pattern, and intent"
                }

                ========================
                FEW-SHOT EXAMPLES
                ========================

                Example 1 — Confirmed Task

                Input:
                - User opens Google Calendar
                - Creates event: "Team Sync at 3PM"
                - Clicks "Save"

                Output:
                {
                "activity_summary": "User used Google Calendar to create and confirm a meeting event.",
                "To-Do List": [
                    {
                    "task": "Attend Team Sync at 3PM",
                    "source": "Google Calendar",
                    "evidence": "User clicked 'Save' after creating the event"
                    }
                ],
                "behavioral_insight": "User is in execution mode, focusing on scheduling and committing to planned activities."
                }

                Example 2 — No Confirmation

                Input:
                - User types a Slack message: "Let's meet tomorrow at 2PM"
                - Does NOT send the message

                Output:
                {
                "activity_summary": "User drafted a message in Slack but did not send it.",
                "To-Do List": [],
                "behavioral_insight": "User is in a planning or drafting phase without committing to actions."
                }

                Example 3 — Partial Information

                Input:
                - User opens email
                - Clicks "Accept meeting"
                - Meeting title not visible

                Output:
                {
                "activity_summary": "User interacted with an email and accepted a meeting invitation.",
                "To-Do List": [
                    {
                    "task": null,
                    "source": "Email",
                    "evidence": "User clicked 'Accept' on a meeting invitation"
                    }
                ],
                "behavioral_insight": "User is responding to incoming requests and confirming participation without reviewing full details."
                }

                ========================
                QUALITY GUIDELINES
                ========================

                - Be concise but precise.
                - Prefer fewer high-confidence items over many uncertain ones.
                - Behavioral insight should reflect:
                - Focus level
                - Task-switching patterns
                - Intent (execution vs exploration)
                """
            }
        ]
    }
]

text = processor.apply_chat_template(
    messages,
    tokenize=False,
    add_generation_prompt=True
)

image_inputs, video_inputs, video_kwargs = process_vision_info(
    messages,
    return_video_kwargs=True
)

video_kwargs["fps"] = video_kwargs.get("fps")[0]

inputs = processor(
    text=[text],
    images=image_inputs,
    videos=video_inputs,
    return_tensors="pt",
    **video_kwargs
)
inputs = inputs.to(model.device)

with torch.no_grad():
    generated_ids = model.generate(
        **inputs,
        max_new_tokens=512
    )

generated_ids_trimmed = [
    out_ids[len(in_ids):]
    for in_ids, out_ids in zip(inputs.input_ids, generated_ids)
]

output = processor.batch_decode(
    generated_ids_trimmed,
    skip_special_tokens=True
)[0]

print(output)