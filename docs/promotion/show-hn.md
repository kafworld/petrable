# Show HN

**Title:** Show HN: Petrable — open-source iPhone app that builds apps using free AI models

**Body:**

Petrable is an open-source iPhone app that lets you type or speak a prompt and get back a working app.

Stack:

- SwiftUI front end
- Convex backend + real-time subscriptions
- Chain of free AI providers: Gemini, Groq, NVIDIA, GitHub Models, OpenRouter, Cerebras, Cloudflare, Ollama
- Web builds run in Daytona sandboxes
- Native iOS builds compile in the cloud via Chorus and install over-the-air

There is no sign-in and no subscription. You add free-tier API keys to your own Convex deployment; the backend falls through providers automatically so one key is enough to start.

I built it because I kept meeting people who wanted to build something but couldn’t keep paying for every AI SaaS. Open source should be the safety net, not the afterthought.

Repo: https://github.com/kafworlddigital/petrable  
Made by: **[KAF World Digital](https://kafworlddigital.com)**

I’d love feedback, especially on the provider chain and the iOS build flow.

---

*If you prefer a hosted, managed tool, Lovable and Replit are solid. Petrable is the open-source, run-it-yourself option for folks who want their own keys and zero recurring cost.*
