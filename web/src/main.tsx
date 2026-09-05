import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import App from "./ui/App";
import { applyStoredTheme } from "./sync/config";

applyStoredTheme();

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
