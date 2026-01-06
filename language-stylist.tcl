#!/usr/bin/wish

# Language Stylist - A hotkey-invoked text transformation tool
# Copyright (c) 2025

#==============================================================================
# GLOBAL CONFIGURATION
#==============================================================================

set ::APP_DIR [file dirname [file normalize [info script]]]
set ::CONFIG_FILE [file join $::APP_DIR "current-mode.conf"]
set ::DEEPSEEK_CONFIG [file join $::APP_DIR "deepseek.json"]
set ::STYLES_DIR [file join $::APP_DIR "styles"]
set ::SYSTEM_PROMPTS_FILE [file join $::APP_DIR "system-prompts.yaml"]

# System prompt components (loaded from YAML)
set ::userTextPrefix ""
set ::singlePassPrefix ""

# First-pass analysis prompt (semantic guardrails)
set ::FIRST_PASS_PROMPT {You are a semantic analysis assistant. Your task is to analyze the input text and identify elements that must be preserved during style editing.

Analyze the text and output ONLY valid JSON with this structure:
{
  "preserve": [
    {"span": "exact text", "reason": "why it must be kept", "category": "proper_noun|domain_term|qualifier_semantic|constraint|other"}
  ],
  "intensifiers": [
    {"span": "word", "keep": true|false, "reason": "literal meaning vs stylistic emphasis", "confidence": 0-100}
  ],
  "ambiguities": [
    {
      "span": "ambiguous text",
      "interpretations": [
        {"meaning": "interpretation A", "probability": 70, "evidence": "why this is likely"},
        {"meaning": "interpretation B", "probability": 30, "evidence": "why this is less likely"}
      ]
    }
  ],
  "ordering": {
    "text_type": "narrative|instruction|request|memo|task|mixed",
    "setting": ["who/where/situation that frames everything else - e.g. 'we are foreign travellers with a rental car'"],
    "events": ["what happened, timeline, incident details - in their natural sequence"],
    "payload": ["the main point: request/question/action/conclusion"],
    "recommended_order": ["setting", "events", "payload"],
    "reasoning": "why this ordering makes sense for this text"
  },
  "rewrite_constraints": ["constraint 1", "constraint 2"]
}

Guidelines:
1. PRESERVED TERMS: Identify domain terms, proper nouns, and semantic qualifiers that carry specific meaning. Context determines whether a word is a term:
   - "VIP list" in "if guests are on the VIP list" = domain term (a specific list), must preserve
   - "VIP" in "feels like a VIP" = figurative, can be rewritten
   - "board resolution" = legal document distinct from meeting minutes, must preserve
   - "dire need" when discussing paying customers/startup failure = semantic qualifier encoding urgency, must preserve

2. INTENSIFIERS: Analyze words that look like intensifiers (very, extremely, dire, critical, suicidal, etc.):
   - If literal/semantic (e.g., "suicidal" in medical context with warning signs) → keep: true, high confidence
   - If hyperbolic/stylistic (e.g., "suicidal" describing a risky business decision) → keep: false, lower confidence

3. AMBIGUITIES: Identify sentences with multiple valid interpretations. Use surrounding context to assign probabilities:
   - "sleep time to be blocked and 30min / 15min links are made" has two interpretations:
     A) sleep time blocked; booking links created (more likely if context is about setting up interviews)
     B) both items blocked (less likely given "links are made" implies creation)

4. ORDERING: Identify three distinct layers and their optimal sequence:
   - SETTING = who/where/situation that frames everything (e.g., "we are foreign travellers with a rental car in Edinburgh"). This establishes the reader's frame of reference.
   - EVENTS = what happened, timeline, incident details. For narratives, chronological order often IS the argument (timestamps as evidence). For instructions, step order is usually intentional.
   - PAYLOAD = the main point: request, question, conclusion, action items.
   
   Typical patterns:
   - Narrative seeking help: setting → events → question (reader needs to know WHO before understanding WHAT happened)
   - Instruction/memo: payload first OR setting → steps
   - Request with justification: setting → reasoning → request
   
   Analyse what ordering best serves the text's purpose. If the author buried the setting at the end but it logically should frame the whole text, recommend moving it first.

5. REWRITE CONSTRAINTS: Provide clear instructions for the style pass, e.g.:
   - "Preserve 'dire need' - encodes urgency and willingness-to-pay"
   - "Treat 'sleep time to be blocked' and '30min/15min links are made' as two separate actions"
   - "Lead with setting 'foreign travellers with rental car in Edinburgh' before the incident timeline"

Output ONLY the JSON object, no other text.}

# Test mode flag
set ::TEST_MODE 0

# Auto-close mode: auto-transform with saved prompt and copy result to clipboard
set ::AUTOCLOSE_MODE 0

# Two-pass mode: use semantic analysis first pass (default is 1-pass)
set ::TWO_PASS_MODE 0

# Current state
set ::currentPrompt ""
set ::clipboardText ""
set ::transformedText ""

# Per-tab HTTP tokens (array indexed by tab index)
array set ::httpTokens {}

# API configuration
set ::apiKey ""
set ::apiBase ""
set ::apiModel ""

# Log file for debugging two-pass pipeline
set ::LOG_FILE [file join $::APP_DIR "language-stylist.log"]

# First-pass analysis result (per tab)
array set ::firstPassResult {}

#==============================================================================
# ARGUMENT PARSING
#==============================================================================

proc parseArguments {} {
    global argv TEST_MODE AUTOCLOSE_MODE TWO_PASS_MODE

    package require cmdline

    set options {
        {test         "Run in test mode"}
        {autoclose    "Auto-transform and close"}
        {auto-close   "Auto-transform and close (alias)"}
        {2pass        "Enable two-pass semantic analysis"}
        {two-pass     "Enable two-pass semantic analysis (alias)"}
    }

    if {[catch {
        array set params [::cmdline::getoptions argv $options]
    } err]} {
        puts stderr "Usage: language-stylist.tcl \[options\]"
        puts stderr [::cmdline::usage $options]
        exit 1
    }

    if {$params(test)} {
        set TEST_MODE 1
    }
    if {$params(autoclose) || $params(auto-close)} {
        set AUTOCLOSE_MODE 1
    }
    if {$params(2pass) || $params(two-pass)} {
        set TWO_PASS_MODE 1
    }
}

#==============================================================================
# CONFIGURATION MANAGEMENT
#==============================================================================

proc loadSessionConfig {} {
    global CONFIG_FILE currentPrompt
    
    if {[file exists $CONFIG_FILE]} {
        if {[catch {
            set f [open $CONFIG_FILE r]
            set data [read $f]
            close $f
            set currentPrompt [string trim $data]
        } err]} {
            # If error reading config, just use empty default
            set currentPrompt ""
        }
    }
}

proc saveSessionConfig {promptName} {
    global CONFIG_FILE
    
    if {[catch {
        set f [open $CONFIG_FILE w]
        puts -nonewline $f $promptName
        close $f
    } err]} {
        # Silent fail on config save error
    }
}

proc loadDeepSeekConfig {} {
    global DEEPSEEK_CONFIG apiKey apiBase apiModel
    
    if {![file exists $DEEPSEEK_CONFIG]} {
        showError "Configuration file missing: deepseek.json\n\nPlease create deepseek.json with your API key."
        exit 1
    }
    
    if {[catch {
        package require json
        set f [open $DEEPSEEK_CONFIG r]
        set data [read $f]
        close $f
        
        set config [json::json2dict $data]
        
        if {[dict exists $config api_key]} {
            set apiKey [dict get $config api_key]
        } else {
            set apiKey ""
        }
        
        if {[dict exists $config api_base]} {
            set apiBase [dict get $config api_base]
        } else {
            set apiBase "https://api.deepseek.com"
        }
        
        if {[dict exists $config model]} {
            set apiModel [dict get $config model]
        } else {
            set apiModel "deepseek-chat"
        }
        
        if {$apiKey eq ""} {
            showError "API key not found in deepseek.json\n\nPlease add your DeepSeek API key to the configuration file."
            exit 1
        }
    } err]} {
        showError "Error loading DeepSeek configuration:\n$err"
        exit 1
    }
}

#==============================================================================
# PROMPT MANAGEMENT
#==============================================================================

# Structure: list of {name filepath content}
set ::prompts {}

proc loadSystemPrompts {} {
    global SYSTEM_PROMPTS_FILE userTextPrefix singlePassPrefix

    if {![file exists $SYSTEM_PROMPTS_FILE]} {
        showError "System prompts file not found: $SYSTEM_PROMPTS_FILE"
        exit 1
    }

    if {[catch {
        package require yaml
        set f [open $SYSTEM_PROMPTS_FILE r]
        set data [read $f]
        close $f

        set config [yaml::yaml2dict $data]

        if {[dict exists $config user_text_prefix]} {
            set userTextPrefix [dict get $config user_text_prefix]
        } else {
            set userTextPrefix ""
        }

        if {[dict exists $config single_pass_prefix]} {
            set singlePassPrefix [dict get $config single_pass_prefix]
        } else {
            set singlePassPrefix ""
        }
    } err]} {
        showError "Error loading system prompts:\n$err"
        exit 1
    }
}

proc loadPrompts {} {
    global STYLES_DIR prompts

    set prompts {}

    if {![file exists $STYLES_DIR] || ![file isdirectory $STYLES_DIR]} {
        showError "Styles directory not found: $STYLES_DIR"
        exit 1
    }

    set files [glob -nocomplain -directory $STYLES_DIR *.txt]
    set files [lsort $files]
    
    if {[llength $files] == 0} {
        showError "No style files found in styles directory."
        exit 1
    }
    
    foreach filepath [lrange $files 0 9] {
        set filename [file tail $filepath]
        set name [file rootname $filename]
        
        if {[catch {
            set f [open $filepath r]
            set content [read $f]
            close $f
            lappend prompts [list $name $filepath $content]
        } err]} {
            # Skip files that can't be read
        }
    }
    
    if {[llength $prompts] == 0} {
        showError "Could not load any valid prompt files."
        exit 1
    }
}

proc getPromptContent {promptName} {
    global prompts
    
    foreach prompt $prompts {
        lassign $prompt name filepath content
        if {$name eq $promptName} {
            return $content
        }
    }
    return ""
}

#==============================================================================
# CLIPBOARD MANAGEMENT
#==============================================================================

proc readClipboard {} {
    global clipboardText
    
    # Try UTF8_STRING first for proper Unicode support
    if {[catch {clipboard get -type UTF8_STRING} content]} {
        # Fall back to default STRING type if UTF8_STRING not available
        if {[catch {clipboard get} content]} {
            return 0
        }
    }
    
    set content [string trim $content]
    if {$content eq ""} {
        return 0
    }
    
    set clipboardText $content
    return 1
}

#==============================================================================
# LOGGING
#==============================================================================

proc logPipelineRun {original firstPassJson stylePrompt finalOutput} {
    global LOG_FILE

    set timestamp [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]
    set delimiter "================================================================================"

    if {[catch {
        set f [open $LOG_FILE a]
        puts $f $delimiter
        puts $f "TIMESTAMP: $timestamp"
        puts $f $delimiter
        puts $f "\n--- ORIGINAL INPUT ---"
        puts $f $original
        puts $f "\n--- FIRST-PASS ANALYSIS (JSON) ---"
        puts $f $firstPassJson
        puts $f "\n--- STYLE PROMPT ---"
        puts $f $stylePrompt
        puts $f "\n--- FINAL OUTPUT ---"
        puts $f $finalOutput
        puts $f "\n"
        close $f
    } err]} {
        puts stderr "WARNING: Could not write to log file: $err"
    }
}

#==============================================================================
# ERROR HANDLING
#==============================================================================

proc showError {message} {
    global TEST_MODE AUTOCLOSE_MODE
    
    # Always log to stderr for debugging
    puts stderr "ERROR: $message"
    
    if {$TEST_MODE} {
        exit 1
    } elseif {$AUTOCLOSE_MODE} {
        # In autoclose mode, show brief dialog then exit with error
        wm title . "Language Stylist - Error"
        wm geometry . 400x200
        
        pack [frame .f -padx 20 -pady 20] -fill both -expand 1
        pack [label .f.msg -text $message -wraplength 360 -justify left] -pady 10
        pack [ttk::button .f.ok -text "OK" -command {exit 1}] -pady 10
        
        # Auto-close after 5 seconds with error code
        after 5000 {exit 1}
    } else {
        # Create error dialog
        wm title . "Language Stylist - Error"
        wm geometry . 400x200
        
        pack [frame .f -padx 20 -pady 20] -fill both -expand 1
        pack [label .f.msg -text $message -wraplength 360 -justify left] -pady 10
        pack [ttk::button .f.ok -text "OK" -command exit] -pady 10
        
        # Auto-close after 3 seconds
        after 3000 exit
    }
}

#==============================================================================
# UI CREATION
#==============================================================================

# Global notebook widget reference
set ::notebook ""

# Maps tab index to text widget path (lazy creation)
array set ::tabTextWidgets {}

# Track which tabs are being processed (array: tabIdx -> 1 if processing)
array set ::processingTabs {}

proc createUI {} {
    global clipboardText prompts currentPrompt TEST_MODE notebook

    wm title . "Language Stylist"

    if {$TEST_MODE} {
        wm withdraw .
    } else {
        wm geometry . 700x600
    }

    # Top Frame - Original Text
    pack [ttk::frame .top -padding 10] -fill both -expand 0
    pack [ttk::label .top.label -text "Original Text:"] -anchor w
    pack [ttk::frame .top.textframe -relief sunken -borderwidth 1] -fill both -expand 1
    text .top.text -height 8 -width 80 -wrap word -state disabled \
        -background #f0f0f0 -relief flat
    pack .top.text -in .top.textframe -fill both -expand 1

    # Insert clipboard text
    .top.text configure -state normal
    .top.text insert 1.0 $clipboardText
    .top.text configure -state disabled

    # Middle Frame - Style Tabs (text widgets created lazily on first use)
    pack [ttk::frame .middle -padding 10] -fill both -expand 1

    set notebook [ttk::notebook .middle.tabs]
    pack $notebook -fill both -expand 1

    set idx 0
    foreach prompt $prompts {
        lassign $prompt name filepath content

        # Create empty frame for each tab (text widget added on first click)
        set tabFrame [ttk::frame $notebook.tab$idx]
        $notebook add $tabFrame -text $name

        # Keyboard binding (1-9, 0 for 10th)
        set key [expr {($idx + 1) % 10}]
        bind . $key [list selectTabByIndex $idx]

        incr idx
    }

    # Bind tab change event
    bind $notebook <<NotebookTabChanged>> onTabChanged
}

proc selectTabByIndex {idx} {
    global notebook
    $notebook select $idx
}

proc createTabTextWidget {tabIdx} {
    global notebook tabTextWidgets

    set tabFrame $notebook.tab$tabIdx
    set textWidget $tabFrame.text

    # Create text widget inside tab frame
    pack [ttk::frame $tabFrame.textframe -relief sunken -borderwidth 1] \
        -fill both -expand 1 -padx 5 -pady 5
    text $textWidget -height 15 -width 80 -wrap word -state disabled -relief flat
    pack $textWidget -in $tabFrame.textframe -fill both -expand 1

    # Store reference
    set tabTextWidgets($tabIdx) $textWidget
    return $textWidget
}

proc onTabChanged {} {
    global notebook prompts currentPrompt tabTextWidgets

    set tabIdx [$notebook index current]
    if {$tabIdx < 0 || $tabIdx >= [llength $prompts]} {
        return
    }

    set promptName [lindex [lindex $prompts $tabIdx] 0]
    set tabFrame $notebook.tab$tabIdx

    # Check if text widget exists (lazy creation)
    if {![winfo exists $tabFrame.text]} {
        # First click on this tab - create widget and call API
        createTabTextWidget $tabIdx
        selectPrompt $promptName $tabIdx
        return
    }

    # Widget exists - check its content
    set content [string trim [$tabFrame.text get 1.0 end]]

    if {[string match "Processing*" $content]} {
        # Already processing, do nothing
        return
    }

    # Cached result - just update currentPrompt for session save
    set currentPrompt $promptName
    saveSessionConfig $promptName
}

#==============================================================================
# PROMPT SELECTION AND TRANSFORMATION
#==============================================================================

proc selectPrompt {promptName tabIdx} {
    global currentPrompt processingTabs

    # Skip if already processing this tab
    if {[info exists processingTabs($tabIdx)] && $processingTabs($tabIdx)} {
        return
    }

    set currentPrompt $promptName
    set processingTabs($tabIdx) 1
    saveSessionConfig $promptName

    # Start transformation for this tab (concurrent with other tabs)
    transformText $tabIdx
}

proc transformText {tabIdx} {
    global currentPrompt clipboardText tabTextWidgets prompts TWO_PASS_MODE

    # Get the prompt name for this specific tab
    set promptName [lindex [lindex $prompts $tabIdx] 0]

    set systemPrompt [getPromptContent $promptName]
    if {$systemPrompt eq ""} {
        displayErrorInTab $tabIdx "Could not load prompt: $promptName"
        return
    }

    # Update UI to show processing in the specific tab
    set textWidget $tabTextWidgets($tabIdx)
    $textWidget configure -state normal -background #f5f5f5
    $textWidget delete 1.0 end

    if {$TWO_PASS_MODE} {
        # Two-pass mode: semantic analysis first, then style
        $textWidget insert 1.0 "Doing 1st pass (semantic analysis)..."
        $textWidget configure -state disabled
        puts stderr "INFO: Doing 1st pass (semantic analysis) for tab $tabIdx"
        callFirstPassAPI $clipboardText $tabIdx $promptName
    } else {
        # Single-pass mode: direct style transformation
        $textWidget insert 1.0 "Processing..."
        $textWidget configure -state disabled
        puts stderr "INFO: Doing single-pass style transformation for tab $tabIdx"
        callSinglePassAPI $clipboardText $tabIdx $promptName
    }
}

#==============================================================================
# JSON ENCODING HELPERS
#==============================================================================

proc jsonEscape {str} {
    # Escape special characters for JSON string
    # JSON requires escaping: backslash, quote, and control characters
    
    set result ""
    set len [string length $str]
    
    for {set i 0} {$i < $len} {incr i} {
        set char [string index $str $i]
        set code [scan $char %c]
        
        # Handle standard escapes
        switch -- $char {
            "\\" { append result "\\\\" }
            "\"" { append result "\\\"" }
            "\n" { append result "\\n" }
            "\r" { append result "\\r" }
            "\t" { append result "\\t" }
            "\b" { append result "\\b" }
            "\f" { append result "\\f" }
            default {
                if {$code < 32} {
                    # Control characters
                    append result [format "\\u%04x" $code]
                } else {
                    # Regular character (including UTF-8)
                    append result $char
                }
            }
        }
    }
    return $result
}

proc jsonString {str} {
    return "\"[jsonEscape $str]\""
}

proc buildJSONPayload {model systemPrompt userText} {
    # Manually construct JSON payload for DeepSeek API
    set escapedModel [jsonEscape $model]
    set escapedSystem [jsonEscape $systemPrompt]
    set escapedUser [jsonEscape $userText]
    
    set json "\{\"model\":\"$escapedModel\","
    append json "\"messages\":\["
    append json "\{\"role\":\"system\",\"content\":\"$escapedSystem\"\},"
    append json "\{\"role\":\"user\",\"content\":\"$escapedUser\"\}"
    append json "\],"
    append json "\"temperature\":0.7,"
    append json "\"max_tokens\":2000\}"
    return $json
}

#==============================================================================
# SINGLE-PASS API CALL
#==============================================================================

proc callSinglePassAPI {originalText tabIdx promptName} {
    global apiKey apiBase apiModel httpTokens userTextPrefix singlePassPrefix

    package require http
    package require tls

    # Register TLS with proper options
    if {[catch {
        ::tls::init -autoservername true
        http::register https 443 [list ::tls::socket -autoservername true]
    } err]} {
        # Fallback for older tls versions
        http::register https 443 ::tls::socket
    }

    # Get the style guide and combine with single-pass prefix
    set styleGuide [getPromptContent $promptName]
    set systemPrompt "${singlePassPrefix}\n${styleGuide}"

    # Build JSON payload
    set wrappedText "${userTextPrefix}${originalText}\n"
    set jsonPayload [buildJSONPayload $apiModel $systemPrompt $wrappedText]
    set jsonPayload [encoding convertto utf-8 $jsonPayload]

    set url "${apiBase}/chat/completions"
    set headers [list \
        Authorization "Bearer $apiKey" \
        Content-Type "application/json; charset=utf-8"]

    # Make async request
    if {[catch {
        puts stderr "INFO: Making single-pass API request for tab $tabIdx"
        set token [http::geturl $url \
            -method POST \
            -headers $headers \
            -type "application/json" \
            -query $jsonPayload \
            -timeout 60000 \
            -command [list handleSinglePassResponse $tabIdx $originalText $promptName]]
        set httpTokens($tabIdx) $token
    } err]} {
        displayErrorInTab $tabIdx "Failed to make API request:\n$err"
    }
}

proc handleSinglePassResponse {tabIdx originalText promptName token} {
    global httpTokens transformedText TEST_MODE processingTabs

    # Clear this tab's token and processing state
    if {[info exists httpTokens($tabIdx)]} {
        unset httpTokens($tabIdx)
    }
    set processingTabs($tabIdx) 0

    set status [http::status $token]
    set ncode [http::ncode $token]
    set data [encoding convertfrom utf-8 [http::data $token]]

    http::cleanup $token

    if {$status ne "ok"} {
        displayErrorInTab $tabIdx "Network error: $status"
        return
    }

    if {$ncode != 200} {
        displayErrorInTab $tabIdx "API error (HTTP $ncode):\n$data"
        return
    }

    # Parse response
    if {[catch {
        package require json
        set response [json::json2dict $data]

        if {[dict exists $response choices]} {
            set choices [dict get $response choices]
            set firstChoice [lindex $choices 0]
            if {[dict exists $firstChoice message content]} {
                set transformedText [dict get $firstChoice message content]
                # Replace em dash with regular dash (em dash is considered an AI marker)
                set transformedText [string map {— " - "} $transformedText]

                # Log the run (with empty analysis for single-pass)
                logPipelineRun $originalText "{}" $promptName $transformedText

                displayResultInTab $tabIdx $transformedText
            } else {
                displayErrorInTab $tabIdx "Unexpected API response format: missing message content"
            }
        } else {
            displayErrorInTab $tabIdx "Unexpected API response format: missing choices"
        }
    } err opt]} {
        set errorInfo [dict get $opt -errorinfo]
        displayErrorInTab $tabIdx "Error processing API response:\n$err\n\nDetails:\n$errorInfo"
    }
}

#==============================================================================
# TWO-PASS PIPELINE API CALLS
#==============================================================================

proc callFirstPassAPI {originalText tabIdx promptName} {
    global apiKey apiBase apiModel httpTokens FIRST_PASS_PROMPT userTextPrefix

    package require http
    package require tls

    # Register TLS with proper options
    if {[catch {
        ::tls::init -autoservername true
        http::register https 443 [list ::tls::socket -autoservername true]
    } err]} {
        # Fallback for older tls versions
        http::register https 443 ::tls::socket
    }

    # Build JSON payload for first pass
    set wrappedText "${userTextPrefix}${originalText}\n"
    set jsonPayload [buildJSONPayload $apiModel $FIRST_PASS_PROMPT $wrappedText]
    set jsonPayload [encoding convertto utf-8 $jsonPayload]

    set url "${apiBase}/chat/completions"
    set headers [list \
        Authorization "Bearer $apiKey" \
        Content-Type "application/json; charset=utf-8"]

    # Make async request
    if {[catch {
        puts stderr "INFO: Making first-pass API request for tab $tabIdx"
        set token [http::geturl $url \
            -method POST \
            -headers $headers \
            -type "application/json" \
            -query $jsonPayload \
            -timeout 60000 \
            -command [list handleFirstPassResponse $tabIdx $originalText $promptName]]
        set httpTokens($tabIdx) $token
    } err]} {
        displayErrorInTab $tabIdx "Failed to make first-pass API request:\n$err"
    }
}

proc handleFirstPassResponse {tabIdx originalText promptName token} {
    global httpTokens firstPassResult tabTextWidgets

    # Clear this tab's token
    if {[info exists httpTokens($tabIdx)]} {
        unset httpTokens($tabIdx)
    }

    set status [http::status $token]
    set ncode [http::ncode $token]
    set data [encoding convertfrom utf-8 [http::data $token]]

    http::cleanup $token

    if {$status ne "ok"} {
        displayErrorInTab $tabIdx "Network error in first pass: $status"
        return
    }

    if {$ncode != 200} {
        displayErrorInTab $tabIdx "API error in first pass (HTTP $ncode):\n$data"
        return
    }

    # Parse response and extract JSON
    if {[catch {
        package require json
        set response [json::json2dict $data]

        if {[dict exists $response choices]} {
            set choices [dict get $response choices]
            set firstChoice [lindex $choices 0]
            if {[dict exists $firstChoice message content]} {
                set analysisJson [dict get $firstChoice message content]

                # Try to extract JSON from the response (in case there's extra text)
                set analysisJson [extractJSON $analysisJson]

                # Validate it's valid JSON
                if {[catch {json::json2dict $analysisJson} parsed]} {
                    puts stderr "WARNING: First pass returned invalid JSON, retrying with stricter prompt"
                    retryFirstPassStrict $tabIdx $originalText $promptName
                    return
                }

                # Store the first-pass result
                set firstPassResult($tabIdx) $analysisJson
                puts stderr "INFO: First pass complete for tab $tabIdx"

                # Now proceed to second pass (style rewrite)
                callSecondPassAPI $tabIdx $originalText $promptName $analysisJson
            } else {
                displayErrorInTab $tabIdx "First pass: unexpected response format (missing message content)"
            }
        } else {
            displayErrorInTab $tabIdx "First pass: unexpected response format (missing choices)"
        }
    } err opt]} {
        set errorInfo [dict get $opt -errorinfo]
        displayErrorInTab $tabIdx "Error processing first-pass response:\n$err\n\nDetails:\n$errorInfo"
    }
}

proc extractJSON {text} {
    # Try to extract JSON object from text that may have extra content
    set start [string first "\{" $text]
    if {$start == -1} {
        return $text
    }

    # Find matching closing brace
    set depth 0
    set inString 0
    set escape 0
    set len [string length $text]

    for {set i $start} {$i < $len} {incr i} {
        set char [string index $text $i]

        if {$escape} {
            set escape 0
            continue
        }

        if {$char eq "\\"} {
            set escape 1
            continue
        }

        if {$char eq "\"" && !$escape} {
            set inString [expr {!$inString}]
            continue
        }

        if {!$inString} {
            if {$char eq "\{"} {
                incr depth
            } elseif {$char eq "\}"} {
                incr depth -1
                if {$depth == 0} {
                    return [string range $text $start $i]
                }
            }
        }
    }

    # If no matching brace found, return original
    return $text
}

proc retryFirstPassStrict {tabIdx originalText promptName} {
    global apiKey apiBase apiModel httpTokens FIRST_PASS_PROMPT userTextPrefix tabTextWidgets

    # Update UI
    set textWidget $tabTextWidgets($tabIdx)
    $textWidget configure -state normal
    $textWidget delete 1.0 end
    $textWidget insert 1.0 "Retrying 1st pass (stricter JSON)..."
    $textWidget configure -state disabled

    package require http
    package require tls

    # Stricter prompt
    set strictPrompt "${FIRST_PASS_PROMPT}\n\nIMPORTANT: Output ONLY the JSON object. No explanations, no markdown code blocks, no other text. Start with \{ and end with \}."

    set wrappedText "${userTextPrefix}${originalText}\n"
    set jsonPayload [buildJSONPayload $apiModel $strictPrompt $wrappedText]
    set jsonPayload [encoding convertto utf-8 $jsonPayload]

    set url "${apiBase}/chat/completions"
    set headers [list \
        Authorization "Bearer $apiKey" \
        Content-Type "application/json; charset=utf-8"]

    if {[catch {
        puts stderr "INFO: Retrying first-pass with stricter prompt for tab $tabIdx"
        set token [http::geturl $url \
            -method POST \
            -headers $headers \
            -type "application/json" \
            -query $jsonPayload \
            -timeout 60000 \
            -command [list handleFirstPassRetryResponse $tabIdx $originalText $promptName]]
        set httpTokens($tabIdx) $token
    } err]} {
        # Fall back to single-pass on retry failure
        puts stderr "WARNING: First pass retry failed, falling back to single-pass"
        fallbackSinglePass $tabIdx $originalText $promptName
    }
}

proc handleFirstPassRetryResponse {tabIdx originalText promptName token} {
    global httpTokens firstPassResult

    if {[info exists httpTokens($tabIdx)]} {
        unset httpTokens($tabIdx)
    }

    set status [http::status $token]
    set ncode [http::ncode $token]
    set data [encoding convertfrom utf-8 [http::data $token]]

    http::cleanup $token

    if {$status ne "ok" || $ncode != 200} {
        puts stderr "WARNING: First pass retry failed, falling back to single-pass"
        fallbackSinglePass $tabIdx $originalText $promptName
        return
    }

    if {[catch {
        package require json
        set response [json::json2dict $data]
        set choices [dict get $response choices]
        set firstChoice [lindex $choices 0]
        set analysisJson [dict get $firstChoice message content]
        set analysisJson [extractJSON $analysisJson]

        # Validate JSON
        if {[catch {json::json2dict $analysisJson}]} {
            puts stderr "WARNING: First pass retry still invalid JSON, falling back to single-pass"
            fallbackSinglePass $tabIdx $originalText $promptName
            return
        }

        set firstPassResult($tabIdx) $analysisJson
        puts stderr "INFO: First pass retry successful for tab $tabIdx"
        callSecondPassAPI $tabIdx $originalText $promptName $analysisJson
    } err]} {
        puts stderr "WARNING: Error in retry response, falling back to single-pass"
        fallbackSinglePass $tabIdx $originalText $promptName
    }
}

proc fallbackSinglePass {tabIdx originalText promptName} {
    global tabTextWidgets userTextPrefix firstPassResult

    set textWidget $tabTextWidgets($tabIdx)
    $textWidget configure -state normal
    $textWidget delete 1.0 end
    $textWidget insert 1.0 "Doing style pass (fallback mode)..."
    $textWidget configure -state disabled

    puts stderr "WARNING: Using single-pass fallback for tab $tabIdx"

    # Set empty first-pass result
    set firstPassResult($tabIdx) "{\"preserve\":[],\"intensifiers\":[],\"ambiguities\":[],\"rewrite_constraints\":[]}"

    set systemPrompt [getPromptContent $promptName]
    set wrappedText "${userTextPrefix}${originalText}\n"
    callDeepSeekAPI $systemPrompt $wrappedText $tabIdx $originalText
}

proc callSecondPassAPI {tabIdx originalText promptName analysisJson} {
    global apiKey apiBase apiModel httpTokens userTextPrefix tabTextWidgets

    # Update UI
    set textWidget $tabTextWidgets($tabIdx)
    $textWidget configure -state normal
    $textWidget delete 1.0 end
    $textWidget insert 1.0 "Doing style pass..."
    $textWidget configure -state disabled
    puts stderr "INFO: Doing style pass for tab $tabIdx"

    package require http
    package require tls

    # Get the style guide
    set styleGuide [getPromptContent $promptName]

    # Build the second-pass system prompt with constraints
    set secondPassPrompt "You are a style editor. You will receive:
1. A style guide to follow
2. A semantic analysis with preservation constraints
3. The original text to edit

CRITICAL RULES:
- The semantic analysis is AUTHORITATIVE. If there is any conflict between the style guide and the semantic constraints, the semantic constraints WIN.
- DO NOT remove or replace preserved terms unless the analysis explicitly permits alternatives.
- Resolve ambiguities using the interpretation with higher probability from the analysis.
- If ambiguity probabilities are close (within 20 percentage points), keep the original wording for that span.
- Preserve intensifiers marked with \"keep\": true.
- ORDERING: Follow the \"ordering\" analysis. Arrange the output according to \"recommended_order\" (typically: setting → events → payload). Setting establishes who/where/situation. Events are the timeline/incident. Payload is the request/question/conclusion.

=== STYLE GUIDE ===
$styleGuide

=== SEMANTIC ANALYSIS (AUTHORITATIVE) ===
$analysisJson

=== END INSTRUCTIONS ==="

    set wrappedText "${userTextPrefix}${originalText}\n"
    set jsonPayload [buildJSONPayload $apiModel $secondPassPrompt $wrappedText]
    set jsonPayload [encoding convertto utf-8 $jsonPayload]

    set url "${apiBase}/chat/completions"
    set headers [list \
        Authorization "Bearer $apiKey" \
        Content-Type "application/json; charset=utf-8"]

    if {[catch {
        puts stderr "INFO: Making second-pass API request for tab $tabIdx"
        set token [http::geturl $url \
            -method POST \
            -headers $headers \
            -type "application/json" \
            -query $jsonPayload \
            -timeout 60000 \
            -command [list handleSecondPassResponse $tabIdx $originalText $promptName $analysisJson]]
        set httpTokens($tabIdx) $token
    } err]} {
        displayErrorInTab $tabIdx "Failed to make second-pass API request:\n$err"
    }
}

proc handleSecondPassResponse {tabIdx originalText promptName analysisJson token} {
    global httpTokens transformedText TEST_MODE processingTabs

    if {[info exists httpTokens($tabIdx)]} {
        unset httpTokens($tabIdx)
    }
    set processingTabs($tabIdx) 0

    set status [http::status $token]
    set ncode [http::ncode $token]
    set data [encoding convertfrom utf-8 [http::data $token]]

    http::cleanup $token

    if {$status ne "ok"} {
        displayErrorInTab $tabIdx "Network error in style pass: $status"
        return
    }

    if {$ncode != 200} {
        displayErrorInTab $tabIdx "API error in style pass (HTTP $ncode):\n$data"
        return
    }

    if {[catch {
        package require json
        set response [json::json2dict $data]

        if {[dict exists $response choices]} {
            set choices [dict get $response choices]
            set firstChoice [lindex $choices 0]
            if {[dict exists $firstChoice message content]} {
                set transformedText [dict get $firstChoice message content]
                # Replace em dash with regular dash (em dash is considered an AI marker)
                set transformedText [string map {— " - "} $transformedText]

                # Log the pipeline run
                set stylePrompt [getPromptContent $promptName]
                logPipelineRun $originalText $analysisJson $promptName $transformedText

                displayResultInTab $tabIdx $transformedText
            } else {
                displayErrorInTab $tabIdx "Style pass: unexpected response format (missing message content)"
            }
        } else {
            displayErrorInTab $tabIdx "Style pass: unexpected response format (missing choices)"
        }
    } err opt]} {
        set errorInfo [dict get $opt -errorinfo]
        displayErrorInTab $tabIdx "Error processing style pass response:\n$err\n\nDetails:\n$errorInfo"
    }
}

#==============================================================================
# DEEPSEEK API INTEGRATION (legacy single-pass, used for fallback)
#==============================================================================

proc callDeepSeekAPI {systemPrompt userText tabIdx {originalText ""}} {
    global apiKey apiBase apiModel httpTokens
    
    package require http
    package require tls
    
    # Register TLS with proper options
    if {[catch {
        ::tls::init -autoservername true
        http::register https 443 [list ::tls::socket -autoservername true]
    } err]} {
        # Fallback for older tls versions
        http::register https 443 ::tls::socket
    }
    
    # Build JSON payload and encode to UTF-8
    set jsonPayload [buildJSONPayload $apiModel $systemPrompt $userText]
    # Microsoft Graph API (OneDrive) returns:
    # Content-Type: application/json; charset=utf-8
    # When the charset is specified, Tcl's http package automatically decodes the response. Adding encoding convertfrom utf-8 double-decodes it → garbage.

    # LLM APIs (OpenAI/Claude style) often return:
    # Content-Type: application/json
    # Without the charset, Tcl's http package returns raw bytes. You need encoding convertfrom utf-8 to decode properly.

    set jsonPayload [encoding convertto utf-8 $jsonPayload]
    
    set url "${apiBase}/chat/completions"
    set headers [list \
        Authorization "Bearer $apiKey" \
        Content-Type "application/json; charset=utf-8"]
    
    # Make async request with tab-specific callback (using lambda to capture tabIdx)
    if {[catch {
        puts stderr "INFO: Making API request to $url for tab $tabIdx"
        set token [http::geturl $url \
            -method POST \
            -headers $headers \
            -type "application/json" \
            -query $jsonPayload \
            -timeout 30000 \
            -command [list handleAPIResponse $tabIdx]]
        # Store token per tab for cleanup purposes
        set httpTokens($tabIdx) $token
    } err]} {
        displayErrorInTab $tabIdx "Failed to make API request:\n$err"
    }
}

proc handleAPIResponse {tabIdx token} {
    global httpTokens transformedText TEST_MODE processingTabs

    # Clear this tab's token and processing state
    if {[info exists httpTokens($tabIdx)]} {
        unset httpTokens($tabIdx)
    }
    set processingTabs($tabIdx) 0

    set status [http::status $token]
    set ncode [http::ncode $token]
    set data [encoding convertfrom utf-8 [http::data $token]]

    http::cleanup $token

    if {$status ne "ok"} {
        displayErrorInTab $tabIdx "Network error: $status"
        return
    }

    if {$ncode != 200} {
        displayErrorInTab $tabIdx "API error (HTTP $ncode):\n$data"
        return
    }

    # Parse response
    if {[catch {
        package require json
        set response [json::json2dict $data]

        if {[dict exists $response choices]} {
            set choices [dict get $response choices]
            set firstChoice [lindex $choices 0]
            if {[dict exists $firstChoice message content]} {
                set transformedText [dict get $firstChoice message content]
                # Replace em dash with regular dash (em dash is considered an AI marker)
                set transformedText [string map {— " - "} $transformedText]
                displayResultInTab $tabIdx $transformedText
            } else {
                displayErrorInTab $tabIdx "Unexpected API response format: missing message content"
            }
        } else {
            displayErrorInTab $tabIdx "Unexpected API response format: missing choices"
        }

    } err opt]} {
        set errorInfo [dict get $opt -errorinfo]
        displayErrorInTab $tabIdx "Error processing API response:\n$err\n\nDetails:\n$errorInfo"
    }
}

proc displayResultInTab {tabIdx text} {
    global TEST_MODE AUTOCLOSE_MODE tabTextWidgets

    if {$TEST_MODE} {
        puts $text
        exit 0
    } else {
        set textWidget $tabTextWidgets($tabIdx)
        $textWidget configure -state normal -background white
        $textWidget delete 1.0 end
        $textWidget insert 1.0 $text
        $textWidget configure -state disabled

        # Auto-copy to clipboard
        clipboard clear
        clipboard append $text
        puts stderr "INFO: Transformed text copied to clipboard"

        if {$AUTOCLOSE_MODE} {
            puts stderr "SUCCESS: Transformation complete, exiting"
            after 100 cleanupAndExit
        }
    }
}

proc cleanupAndExit {} {
    global httpTokens
    
    # Cancel all pending http operations - must reset before cleanup for in-flight requests
    foreach tabIdx [array names httpTokens] {
        catch {http::reset $httpTokens($tabIdx)}
        catch {http::cleanup $httpTokens($tabIdx)}
    }
    array unset httpTokens
    
    # Unregister https to prevent cleanup errors
    catch {http::unregister https}
    
    # Now destroy the window
    destroy .
}

proc displayErrorInTab {tabIdx message} {
    global TEST_MODE AUTOCLOSE_MODE tabTextWidgets processingTabs

    # Reset processing state for this tab
    set processingTabs($tabIdx) 0

    # Always log to stderr for debugging
    puts stderr "ERROR: $message"

    if {$TEST_MODE} {
        flush stderr
        exit 1
    } elseif {$AUTOCLOSE_MODE} {
        flush stderr
        flush stdout
        cleanupAndExit
    } else {
        set textWidget $tabTextWidgets($tabIdx)
        $textWidget configure -state normal -background #ffe0e0
        $textWidget delete 1.0 end
        $textWidget insert 1.0 "Error:\n\n$message"
        $textWidget configure -state disabled
    }
}


#==============================================================================
# MAIN ENTRY POINT
#==============================================================================

proc main {} {
    global currentPrompt prompts AUTOCLOSE_MODE TWO_PASS_MODE notebook

    # Parse command line arguments
    parseArguments

    if {$TWO_PASS_MODE} {
        puts stderr "INFO: Two-pass mode enabled (semantic analysis + style)"
    } else {
        puts stderr "INFO: Single-pass mode (default)"
    }

    if {$AUTOCLOSE_MODE} {
        puts stderr "INFO: Autoclose mode enabled"
    }
    
    # Load configurations
    loadDeepSeekConfig
    loadSessionConfig
    loadSystemPrompts
    loadPrompts
    
    # Read clipboard
    if {![readClipboard]} {
        showError "Clipboard is empty or contains unsupported data.\n\nPlease copy some text and try again."
        return
    }
    
    # Create UI
    createUI
    
    # If no saved prompt, use first one
    if {$currentPrompt eq ""} {
        set currentPrompt [lindex [lindex $prompts 0] 0]
    }
    
    # Find the tab index for the current prompt
    set tabIdx 0
    set foundIdx 0
    foreach prompt $prompts {
        if {[lindex $prompt 0] eq $currentPrompt} {
            set foundIdx $tabIdx
            break
        }
        incr tabIdx
    }
    
    if {$AUTOCLOSE_MODE} {
        puts stderr "INFO: Using prompt '$currentPrompt'"
    }
    
    # Select the initial tab - this triggers onTabChanged which starts transformation
    $notebook select $foundIdx
}

# Run main
main


