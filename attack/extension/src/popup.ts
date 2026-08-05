// popup.ts — reads the path input, asks the service worker to forward it
// to the native-messaging bridge, and renders the response.

const input  = document.getElementById("path") as HTMLInputElement;
const button = document.getElementById("go")   as HTMLButtonElement;
const out    = document.getElementById("out")  as HTMLPreElement;

function render(text: string): void {
    out.textContent = text;
}

button.addEventListener("click", () => {
    const path = input.value.trim();
    if (!path) {
        render("error: path is empty");
        return;
    }
    render(`sending: ${path} …`);
    // This callback doesn't run until background.ts's onMessage listener
    // calls sendResponse (see background.ts) — sendMessage itself is
    // fire-and-forget from here, it doesn't block this click handler.
    chrome.runtime.sendMessage({ path }, (reply) => {
        if (chrome.runtime.lastError) {
            render(`runtime error: ${chrome.runtime.lastError.message}`);
            return;
        }
        render(JSON.stringify(reply, null, 2));
    });
});
