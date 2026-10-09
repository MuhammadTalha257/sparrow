# Zuffi Business server (always-on WhatsApp)

This small server lets Zuffi work 24/7 with the **official WhatsApp Business Platform**, even when the Mac is off.

- **Every WhatsApp chat becomes a lead.** Zuffi fills in name, number, what the client wants, area, budget and how hot they are.
- **Voice notes are written out**, and the details go into the lead.
- **Replies are drafted** in the client's language. If you switch auto-reply on, they're sent straight away.
- **Coexistence:** the business keeps using the WhatsApp Business app on the phone with the same number. Replies sent from the phone are seen too: the lead counts as contacted and its draft is cleared.
- **Facebook and Instagram lead forms arrive instantly** (optional).
- **Team members sign in on their phone** at the server's address with their name and PIN. They see only their own leads, reply and update them.
- **Every hour** Zuffi does three things:
  - sends the owner's daily summary at the chosen hour (new leads, waiting replies, hot leads, follow-ups, who isn't following up);
  - sends each team member their list;
  - drafts follow-ups for leads that have gone quiet.

Everything runs on Cloudflare's free plan: Workers, a D1 database and Workers AI. Add a free Groq key for better Urdu voice notes.

## 1. Put the server online (about 10 minutes)

```bash
cd server
npm install
npx wrangler login
npx wrangler d1 create zuffi-business     # copy the database_id it prints into wrangler.toml
npm run db:init
npx wrangler secret put ADMIN_KEY          # a long random password; you'll paste it into Zuffi
npx wrangler secret put VERIFY_TOKEN       # any word, e.g. zuffi-verify-2026
npm run deploy                             # prints your address, e.g. https://zuffi-wa.<you>.workers.dev
```

Set `TIMEZONE` in `wrangler.toml` to `Asia/Karachi` or `Europe/London`.

## 2. Connect WhatsApp (Meta)

1. Go to [developers.facebook.com](https://developers.facebook.com). Create an app (type **Business**) and add the **WhatsApp** product.
2. Under **WhatsApp → API setup**, add the business number. There are two ways:
   - **Keep the WhatsApp Business app on the phone (Coexistence).** Meta only lets a *Solution Partner* or *Tech Provider* connect an existing app number. So either Zuffi becomes a Meta Tech Provider (free, needs business verification and app review), or the business connects through a partner such as 360dialog, Twilio or Gupshup. The phone needs WhatsApp Business 2.24.17 or newer, must be opened at least every 14 days, and up to 6 months of chats are copied over.
   - **Simpler: a number that isn't on WhatsApp yet** (a new SIM, or remove the WhatsApp account from it first). Add it directly here. The team then works from the Zuffi team page instead of the phone app.
3. Create a **System User** in Business Settings and give it the WhatsApp account. Make a **permanent token** with `whatsapp_business_messaging` and `whatsapp_business_management`. Then:
   ```bash
   npx wrangler secret put WA_TOKEN
   npx wrangler secret put PHONE_NUMBER_ID    # from WhatsApp → API setup
   npx wrangler secret put APP_SECRET         # App settings → Basic → App secret
   ```
4. Set up the webhook under **WhatsApp → Configuration → Webhook**:
   - **Callback URL:** `https://zuffi-wa.<you>.workers.dev/webhook`
   - **Verify token:** the word you chose for VERIFY_TOKEN
   - **Subscribe to:** `messages`, `smb_message_echoes` and `history`
5. Optional, for instant Facebook / Instagram lead forms:
   - Subscribe your Page to `leadgen` (Webhooks → Page, same callback URL).
   - Run `npx wrangler secret put PAGE_TOKEN` and paste a Page access token with `leads_retrieval`.
6. Optional, for better Urdu and Punjabi voice notes and replies: run `npx wrangler secret put GROQ_KEY` (free key from console.groq.com).

## 3. Link Zuffi on the Mac

Open Zuffi → **Business** → **Connect WhatsApp**. Paste the server address and the ADMIN_KEY, then press **Test**. Your team, settings and leads are sent to the server, and new chats show up in the Inbox every minute.

Team members open the server address on their phone and sign in with their name and the PIN shown in **Team**.

## What WhatsApp charges

- Replies within 24 hours of the client's last message are free.
- Clients who come from a Click-to-WhatsApp ad give you a free 72-hour window.
- Messages *you* start after 24 hours (reminders, offers, the daily summary to staff who haven't written to the number that day) need an approved **template** and are charged per message.

For the daily summary, make a Utility template with one body variable, for example `Your Zuffi summary: {{1}}`. Then add `"summary_template": "<template name>"` to the settings. When a normal message isn't allowed, Zuffi sends this template instead.

Meta's 2026 rules allow AI that serves the business (support, bookings, lead questions) and hands over to a person. That's exactly what Zuffi does. It doesn't run a general chatbot on your number.

## Tests

`npm test` runs the whole flow offline with a fake WhatsApp and a real SQLite database:

- Meta's webhook check and the signature check
- a new chat becoming a lead, a voice note becoming a lead, and a reply from the phone app
- an Instagram lead form
- staff sign-in with PIN, and staff seeing only their own leads
- replying, changing the stage, and adding a note
- the Mac app's sync
- the 24-hour rule
- the team report and the daily summary
