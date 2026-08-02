#include "SDMEngineDomain.h"

namespace sdm {

bool can_transition(DownloadState from, DownloadState to) noexcept {
    if (from == to) {
        return true;
    }

    switch (from) {
    case DownloadState::created:
        return to == DownloadState::probing ||
            to == DownloadState::cancelled;
    case DownloadState::probing:
        return to == DownloadState::queued ||
            to == DownloadState::downloading ||
            to == DownloadState::failed ||
            to == DownloadState::cancelled;
    case DownloadState::queued:
        return to == DownloadState::downloading ||
            to == DownloadState::paused ||
            to == DownloadState::cancelled;
    case DownloadState::downloading:
        return to == DownloadState::pausing ||
            to == DownloadState::retrying ||
            to == DownloadState::finalizing ||
            to == DownloadState::failed ||
            to == DownloadState::cancelled;
    case DownloadState::pausing:
        return to == DownloadState::paused ||
            to == DownloadState::failed ||
            to == DownloadState::cancelled;
    case DownloadState::paused:
        return to == DownloadState::queued ||
            to == DownloadState::cancelled;
    case DownloadState::retrying:
        return to == DownloadState::downloading ||
            to == DownloadState::paused ||
            to == DownloadState::failed ||
            to == DownloadState::cancelled;
    case DownloadState::finalizing:
        return to == DownloadState::completed ||
            to == DownloadState::failed;
    case DownloadState::completed:
        return false;
    case DownloadState::failed:
        return to == DownloadState::queued ||
            to == DownloadState::cancelled;
    case DownloadState::cancelled:
        return to == DownloadState::queued;
    }

    return false;
}

Result validate_command(DownloadState state, CommandKind command) noexcept {
    switch (command) {
    case CommandKind::enqueue:
        return state == DownloadState::created
            ? Result::ok
            : Result::invalid_state;
    case CommandKind::pause:
        return state == DownloadState::queued ||
                state == DownloadState::downloading ||
                state == DownloadState::retrying
            ? Result::ok
            : Result::invalid_state;
    case CommandKind::resume:
        return state == DownloadState::paused
            ? Result::ok
            : Result::invalid_state;
    case CommandKind::cancel:
        return state != DownloadState::completed &&
                state != DownloadState::cancelled
            ? Result::ok
            : Result::invalid_state;
    case CommandKind::retry:
        return state == DownloadState::failed ||
                state == DownloadState::cancelled
            ? Result::ok
            : Result::invalid_state;
    case CommandKind::remove:
        return state == DownloadState::completed ||
                state == DownloadState::failed ||
                state == DownloadState::cancelled ||
                state == DownloadState::paused
            ? Result::ok
            : Result::invalid_state;
    }

    return Result::invalid_argument;
}

} // namespace sdm
