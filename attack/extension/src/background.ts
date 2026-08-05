// background.ts — MV3 service worker. Receives {path} from the popup
// and forwards it to the native-messaging host `com.bussie.bridge`,
// which in turn calls org.bussie.Pwn.Delete on the system bus.

const HOST_NAME = "com.bussie.bridge";

// Names are deliberately prefixed to avoid colliding with the DOM globals
// `Request` / `Response` (from the fetch API), whose `readonly` modifiers
// would clash with ours via TS's declaration merging (TS2687).
interface BridgeRequest  { path: string; }
interface BridgeResponse { ok: boolean; result: string; }

chrome.runtime.onMessage.addListener(
    (req: BridgeRequest, _sender, sendResponse) => {
        if (!req || typeof req.path !== "string") {
            sendResponse({ ok: false, result: "bad request from popup" } as BridgeResponse);
            return false;
        }
        chrome.runtime.sendNativeMessage(HOST_NAME, { path: req.path }, (reply) => {
            if (chrome.runtime.lastError) {
                sendResponse({
                    ok: false,
                    result: `native messaging error: ${chrome.runtime.lastError.message}`,
                } as BridgeResponse);
                return;
            }
            sendResponse(reply as BridgeResponse);
        });
        // Returning true tells Chrome this listener will call sendResponse
        // asynchronously — without it, Chrome closes the message channel the
        // instant this function returns, and popup.ts's sendMessage callback
        // fires immediately with reply = undefined. Chrome still caps how
        // long it'll wait, though: if sendResponse is never called, the port
        // auto-closes after ~5 minutes, and the popup callback then fires
        // with chrome.runtime.lastError set to "The message port closed
        // before a response was received." A pending channel also counts as
        // activity that defers this service worker's own ~30s MV3 idle
        // shutdown, so it stays alive to finish the native-messaging round
        // trip above.
        return true;
    }
);
