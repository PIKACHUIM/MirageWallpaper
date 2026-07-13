#include "ControlChannel.h"

#include <cstdio>
#include <iostream>
#include <string>

import sr.json;
import rstd.cppstd;
import sr.scene_wallpaper; // re-exports sr.types (FillMode)

namespace mirage {

namespace {

// Maps the wire fill-mode name (matching WE / the other renderers' vocabulary)
// to sr::FillMode. cover→ASPECTCROP, contain/fit→ASPECTFIT, stretch→STRETCH.
bool ParseFillMode(const std::string& s, sr::FillMode& out) {
    if (s == "cover" || s == "aspectcrop" || s == "crop") {
        out = sr::FillMode::ASPECTCROP;
        return true;
    }
    if (s == "contain" || s == "fit" || s == "aspectfit") {
        out = sr::FillMode::ASPECTFIT;
        return true;
    }
    if (s == "stretch") {
        out = sr::FillMode::STRETCH;
        return true;
    }
    return false;
}

} // namespace

void SceneControlChannel::dispatchLine(const char* line) {
    if (line == nullptr) return;

    auto parsed = sr::ParseJson(line, { .allow_comments = true });
    if (parsed.is_err()) return;
    auto msg = parsed.unwrap();
    if (! msg.is_object()) return;
    auto command = msg.get("cmd");
    if (command.is_none()) return;
    auto command_text = (*command)->as_str();
    if (command_text.is_none()) return;

    const std::string cmd = rstd::cppstd::to_string(*command_text);

    if (cmd == "setProperty") {
        auto key_value = msg.get("key");
        if (key_value.is_none()) return;
        auto key_text = (*key_value)->as_str();
        if (key_text.is_none()) return;
        const std::string key = rstd::cppstd::to_string(*key_text);

        // Build the property descriptor the runtime expects. If an explicit
        // "type" is present (e.g. color), wrap {type,value}; otherwise pass the
        // raw value (bool/number/string) — CoerceUserPropertyValue infers it.
        auto type = msg.get("type");
        auto value = msg.get("value");
        sr::Json prop = sr::Json::Null();
        if (type.is_some() && (*type)->is_string()) {
            auto object = rstd::json::Map::make();
            object.insert(::alloc::string::String::make(rstd::cppstd::as_str("type")),
                          (*type)->clone());
            object.insert(::alloc::string::String::make(rstd::cppstd::as_str("value")),
                          value.is_some() ? (*value)->clone() : sr::Json::Null());
            prop = sr::Json::Object(rstd::move(object));
        } else if (value.is_some()) {
            prop = (*value)->clone();
        } else {
            return;
        }
        m_wallpaper.setUserPropertyJson(key, std::move(prop));
    } else if (cmd == "pause") {
        m_wallpaper.pause();
    } else if (cmd == "resume" || cmd == "play") {
        m_wallpaper.play();
    } else if (cmd == "volume") {
        auto value = msg.get("value");
        if (value.is_some() && (*value)->is_number()) {
            auto number = (*value)->as_f64();
            if (number.is_some()) m_wallpaper.setVolume(static_cast<float>(*number));
        }
    } else if (cmd == "muted") {
        auto value = msg.get("value");
        if (value.is_some() && (*value)->is_boolean()) {
            m_wallpaper.setMuted(*(*value)->as_bool());
        }
    } else if (cmd == "fps") {
        auto value = msg.get("value");
        if (value.is_some() && (*value)->is_number()) {
            auto number = (*value)->as_u64();
            if (number.is_some()) m_wallpaper.setFps(static_cast<std::uint32_t>(*number));
        }
    } else if (cmd == "fillmode") {
        auto value = msg.get("value");
        if (value.is_some() && (*value)->is_string()) {
            sr::FillMode mode {};
            if (ParseFillMode(rstd::cppstd::to_string(*(*value)->as_str()), mode)) {
                m_wallpaper.setFillMode(mode);
            }
        }
    } else if (cmd == "speed") {
        auto value = msg.get("value");
        if (value.is_some() && (*value)->is_number()) {
            auto number = (*value)->as_f64();
            if (number.is_some()) m_wallpaper.setSpeed(static_cast<float>(*number));
        }
    } else if (cmd == "quit") {
        m_running.store(false);
        if (m_on_quit) m_on_quit();
    }
}

void SceneControlChannel::readLoop() {
    std::string line;
    while (m_running.load()) {
        if (! std::getline(std::cin, line)) {
            // EOF or error: the parent closed the pipe (or died). Exit cleanly.
            break;
        }
        if (line.empty()) continue;
        dispatchLine(line.c_str());
    }
    if (m_running.exchange(false)) {
        // Reached here via EOF (not an explicit quit) — still tell the host.
        if (m_on_quit) m_on_quit();
    }
}

} // namespace mirage
