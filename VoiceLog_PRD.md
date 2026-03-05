**VoiceLog**

One-Button Meeting Dictation + Notion Intelligence

*macOS Native Application \| Powered by OpenAI Whisper*

  ------------------ -------------------------------------------------------
  **Product Name**   VoiceLog

  **Platform**       macOS 13 Ventura and later (Apple Silicon + Intel)

  **Version**        1.0 --- Initial Release

  **Author**         Bennett Yetz

  **Date**           March 2026

  **Status**         Draft --- In Review

  **Integrations**   OpenAI Whisper (local), Notion API

  **Distribution**   Personal / Team --- Mac App Store or direct DMG
  ------------------ -------------------------------------------------------

**1. Overview & Problem Statement**

Meetings generate valuable decisions, action items, and context that too
often evaporate because capturing them requires manual effort
mid-conversation. Existing tools either require cloud processing
(privacy risk), are too complex to set up, or don\'t push structured
data into a team\'s existing knowledge base.

VoiceLog is a lightweight macOS menu bar application that lets you start
and stop meeting dictation with a single button press or global hotkey.
Audio is transcribed locally using OpenAI Whisper --- no audio ever
leaves the machine --- and the resulting transcript is automatically
structured and pushed to a designated Notion database, creating a
searchable, permanent meeting record with zero friction.

The result is a closed-loop meeting intelligence system: record →
transcribe → structure → log --- in under 30 seconds of user action.

**2. Goals & Non-Goals**

**Goals**

-   Reduce meeting follow-up overhead by auto-generating Notion meeting
    records

-   Enable fully local, private transcription via Whisper (no cloud
    audio)

-   One-button / one-hotkey UX --- zero friction to start and stop

-   Structured Notion output: title, date, duration, raw transcript, and
    AI-extracted summary + action items

-   Live status indicator in the menu bar (idle / recording /
    transcribing / syncing)

-   Support multiple audio input devices and Notion workspaces

**Non-Goals (v1.0)**

-   Speaker diarization (identifying who said what) --- v2 roadmap

-   Real-time streaming transcription --- Whisper batch processing only

-   Windows or Linux support

-   Calendar integration or auto-triggering from calendar events

-   Zoom / Teams SDK-based bot recording --- captures system mic only

**3. Target Users**

VoiceLog is built for knowledge workers who run or participate in
frequent meetings and use Notion as their primary knowledge management
system. The primary persona:

  ---------------- ------------------------------------------------------
  **Primary        Engineering Manager / Team Lead who attends 5--10
  Persona**        meetings per day, manages distributed teams, and
                   relies on Notion for team documentation, task
                   tracking, and project pages. Values privacy and
                   dislikes context switching.

  ---------------- ------------------------------------------------------

  ---------------- ------------------------------------------------------
  **Secondary      Individual contributor or founder who needs an audit
  Persona**        trail of conversations, decisions, and commitments ---
                   without a dedicated note-taker or EA.

  ---------------- ------------------------------------------------------

**4. Feature Requirements**

**4.1 Core Recording**

-   **Menu Bar App:** VoiceLog lives permanently in the macOS menu bar,
    accessible at all times without interrupting workflow

-   **One-Button Toggle:** A single click on the menu bar icon (or
    global hotkey) starts recording; another click stops it

-   **Global Hotkey:** Configurable keyboard shortcut (default: ⌃⌥R)
    works system-wide, even when VoiceLog is not in focus

-   **Audio Source Selection:** Dropdown in preferences to select any
    available input device (built-in mic, AirPods, external USB mic,
    virtual audio drivers like BlackHole for system audio capture)

-   **Recording Timer:** Live elapsed time shown in the menu bar while
    recording is active

-   **Pause / Resume:** Optional mid-session pause without ending the
    recording session

**4.2 Transcription Engine (Whisper)**

-   **Local Model:** Whisper runs entirely on-device via whisper.cpp or
    the official Python package --- no audio transmitted externally

-   **Model Selection:** User can choose Whisper model size in Settings:
    tiny, base, small, medium (default), large --- with a
    storage/accuracy tradeoff callout

-   **Language Detection:** Automatic language detection; override
    available for non-English meetings

-   **Transcription Progress:** Visual progress bar in the menu bar
    popover while transcription runs after recording stops

-   **Error Handling:** If transcription fails, raw audio is preserved
    locally and user is prompted to retry

**4.3 AI Post-Processing**

-   **Summary:** After transcription, a lightweight LLM call (local via
    Ollama or optional OpenAI API) generates a 3--5 sentence meeting
    summary

-   **Action Items:** Extracts and formats a bulleted list of action
    items with implied owners where detectable

-   **Meeting Title:** Auto-suggests a concise meeting title based on
    content (user can override before sync)

-   **Key Decisions:** Highlights any decisions made during the meeting
    as a separate section

**4.4 Notion Integration**

-   **OAuth Auth:** One-time Notion OAuth flow in Settings --- no manual
    API key copy-paste

-   **Database Target:** User selects which Notion database receives
    meeting records; VoiceLog validates schema on connect

-   **Auto-Schema Creation:** If no target database exists, VoiceLog
    offers to create a pre-configured \'Meeting Log\' database in the
    selected workspace

-   **Page Structure:** Each meeting creates one Notion page: title,
    date, duration, attendees (manual), summary callout block, action
    items checklist, key decisions, and full raw transcript in a toggle
    block

-   **Sync Trigger:** Sync happens automatically after post-processing;
    user sees confirmation toast with a \'View in Notion\' link

-   **Retry Queue:** If sync fails (offline, rate limit), the record is
    queued locally and retried on next app launch

**4.5 Settings & Configuration**

-   **Notion Workspace:** Connect/disconnect workspace, select target
    database

-   **Whisper Model:** Model size selector with disk usage and estimated
    speed shown

-   **Audio Input:** Default microphone selector

-   **Hotkey:** Configurable global hotkey with conflict detection

-   **Post-Processing:** Toggle AI summary on/off; select local (Ollama)
    or cloud (OpenAI) LLM

-   **Local Storage:** Path for raw audio and transcription cache;
    configurable retention (7 / 30 / 90 days / never delete)

-   **Launch at Login:** Toggle to add VoiceLog to macOS login items

**5. Feature Priority & Phasing**

  ---------------------------------------------------------------------------
  **Feature**              **Priority**   **Phase**   **Notes**
  ------------------------ -------------- ----------- -----------------------
  Menu bar icon + toggle   **P0**         v1.0        Core loop --- must ship
  recording                                           

  Whisper local            **P0**         v1.0        Core loop --- must ship
  transcription                                       

  Notion OAuth + page      **P0**         v1.0        Core loop --- must ship
  creation                                            

  Global hotkey            **P0**         v1.0        Critical UX requirement

  Recording timer in menu  **P0**         v1.0        Feedback to user
  bar                                                 

  AI summary + action      **P1**         v1.0        High value; local LLM
  items                                               preferred

  Whisper model selector   **P1**         v1.0        User control over
                                                      quality/speed

  Audio device selector    **P1**         v1.0        Essential for diverse
                                                      setups

  Auto-schema / DB         **P1**         v1.0        Reduces onboarding
  creation                                            friction

  Offline retry queue      **P1**         v1.0        Reliability requirement

  Pause / Resume recording **P2**         v1.1        Nice to have

  Speaker diarization      **P2**         v2.0        Complexity; core ML
                                                      work

  Calendar auto-trigger    **P2**         v2.0        Integration dependency

  System audio capture     **P2**         v1.1        BlackHole dependency

  Attendee auto-detection  **P2**         v2.0        Calendar API needed
  ---------------------------------------------------------------------------

**6. Key User Flows**

**Flow 1: Record a Meeting**

1\. VoiceLog icon is in the menu bar (gray = idle).

2\. User presses ⌃⌥R (or clicks icon) → icon turns red, timer starts.

3\. User attends meeting normally.

4\. User presses ⌃⌥R again (or clicks icon) → recording stops.

5\. Menu bar icon shows a spinner → transcription in progress.

6\. Once complete: AI post-processing runs, result preview appears in
popover.

7\. User can optionally edit the meeting title, then clicks \'Sync to
Notion\'.

8\. Toast notification: \'Meeting logged ✓\' with \'View in Notion\'
CTA.

**Flow 2: First-Time Setup**

1\. User installs VoiceLog and launches it.

2\. Onboarding sheet prompts: Connect Notion → Notion OAuth opens in
browser → authorized.

3\. VoiceLog lists user\'s Notion databases; user picks target or
creates new.

4\. User selects Whisper model (tooltip shows size vs. speed).

5\. User sets global hotkey (default shown, conflict warning if taken).

6\. Done --- VoiceLog enters idle state in the menu bar.

**7. Notion Database Schema**

VoiceLog will validate or create a Notion database with the following
properties:

  -------------------------------------------------------------------------
  **Property Name**  **Notion       **Description**
                     Type**         
  ------------------ -------------- ---------------------------------------
  **Meeting Title**  Title          Auto-suggested from content;
                                    user-editable before sync

  **Date**           Date           Date and start time of the recording

  **Duration**       Number         Recording length in minutes

  **Attendees**      Multi-select   Manually entered or populated from
                                    calendar (v2)

  **Summary**        Rich Text      AI-generated 3--5 sentence meeting
                                    summary

  **Status**         Select         Draft / Reviewed / Archived

  **Whisper Model**  Select         Model size used for this transcription

  **Transcript       Rich Text      Full raw transcript inside a collapsed
  (toggle)**                        toggle block

  **Action Items**   Checkbox list  Checklist of extracted action items on
                                    the page body

  **Key Decisions**  Rich Text      Bulleted decisions block on the page
                                    body
  -------------------------------------------------------------------------

**8. Technical Architecture**

**Technology Stack**

  ---------------- ------------------------------------------------------
  **Frontend /     SwiftUI --- native macOS menu bar app with
  Shell**          NSStatusItem

  ---------------- ------------------------------------------------------

  ---------------- ------------------------------------------------------
  **Audio          AVFoundation --- system mic capture; optional
  Capture**        BlackHole virtual driver for system audio

  ---------------- ------------------------------------------------------

  ------------------- ------------------------------------------------------
  **Transcription**   whisper.cpp (C++ port) via Swift interop or Python
                      subprocess --- fully local, no network

  ------------------- ------------------------------------------------------

  ------------------- ------------------------------------------------------
  **AI                Ollama (local) with llama3 or mistral; fallback to
  Post-Processing**   OpenAI API with user-supplied key

  ------------------- ------------------------------------------------------

  ---------------- ------------------------------------------------------
  **Notion API**   Official Notion REST API v1 --- OAuth 2.0 for auth,
                   Pages and Databases endpoints for write

  ---------------- ------------------------------------------------------

  ---------------- ------------------------------------------------------
  **Local          SQLite via GRDB.swift --- stores session metadata,
  Storage**        retry queue, and transcript cache

  ---------------- ------------------------------------------------------

**Privacy Architecture**

-   All audio processed on-device by default --- no audio bytes sent to
    external servers

-   Transcripts stored encrypted at rest in \~/Library/Application
    Support/VoiceLog/

-   Notion OAuth tokens stored in macOS Keychain

-   AI post-processing runs locally via Ollama unless user opts into
    OpenAI API

-   No telemetry or analytics in v1.0

**9. Edge Cases & Error Handling**

-   **App quit mid-recording:** Audio buffer is flushed to disk;
    transcript attempt made on next launch with recovery prompt

-   **Whisper model not downloaded:** First-run prompt to download
    selected model; progress shown; fallback to smaller model offered

-   **Notion API rate limit:** Exponential backoff with local retry
    queue; user notified via notification

-   **No internet / offline:** Recording and transcription still work;
    Notion sync queued for when connectivity returns

-   **Very long recordings (2h+):** Warning at 90 min; Whisper chunked
    into 10-min segments for performance

-   **Duplicate sync:** Idempotency key (session UUID) prevents
    duplicate Notion pages on retry

-   **Notion token expired:** Silent re-auth prompt before next sync
    attempt; no data loss

**10. Success Metrics**

Because v1.0 is a personal/team tool, success is measured qualitatively
and through usage patterns rather than growth metrics:

  ---------------- ------------------------------------------------------
  **Adoption**     App launched and used ≥ 3x per week within 30 days of
                   install

  ---------------- ------------------------------------------------------

  ----------------- ------------------------------------------------------
  **Reliability**   Zero data-loss events --- every completed recording
                    results in a Notion page

  ----------------- ------------------------------------------------------

  ---------------- ------------------------------------------------------
  **Speed**        Transcription completes in ≤ 1.5× real-time for medium
                   model on Apple Silicon

  ---------------- ------------------------------------------------------

  ---------------- ------------------------------------------------------
  **Friction**     Time from \'stop recording\' to \'Notion page
                   created\' ≤ 90 seconds for a 30-min meeting

  ---------------- ------------------------------------------------------

  ---------------- ------------------------------------------------------
  **UX             User does not need to touch transcript before sync in
  Satisfaction**   ≥ 80% of sessions

  ---------------- ------------------------------------------------------

**11. Roadmap**

  -----------------------------------------------------------------------
  **Version**   **Scope**
  ------------- ---------------------------------------------------------
  **v1.0**      Core loop: record → Whisper → AI summary → Notion. Menu
                bar UI. Setup wizard. Local storage + retry queue.

  **v1.1**      Pause/resume. System audio via BlackHole. Transcript
                editing before sync. Export to Markdown.

  **v2.0**      Speaker diarization (whisper-diarization or pyannote).
                Google Calendar auto-trigger. Multi-database routing by
                calendar event type.

  **v2.5**      Team mode: shared Notion workspace, per-user recordings
                linked to shared meeting pages. Slack summary posting.
  -----------------------------------------------------------------------

**12. Open Questions**

-   **Distribution:** Mac App Store (requires sandboxing, may limit
    whisper.cpp access) vs. direct DMG + Gatekeeper notarization ---
    which path for v1.0?

-   **LLM Default:** Ship with Ollama dependency required, or make AI
    post-processing opt-in to reduce install friction?

-   **Whisper Model Bundling:** Bundle a tiny model in the app for
    zero-config first run, or always require download?

-   **Notion Schema Flexibility:** Should users be able to map VoiceLog
    fields to their existing custom Notion properties, or enforce
    VoiceLog\'s schema?

-   **Pricing:** Free personal tool vs. freemium (unlimited recordings,
    Notion sync gated on subscription)?

*--- End of Document ---*
