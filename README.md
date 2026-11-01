# Guess in 10
React + Vite + Tailwind v4 + Supabase (Postgres, Realtime, RPC).
## Run locally
1. Create a Supabase project. In the SQL editor run `supabase/migrations/001_schema.sql`, then `002_seed.sql`.
2. `cp .env.example .env` and paste your project URL + **anon** key (never the service-role key).
3. `npm install && npm run dev`, then open two browser windows (one private) to play.
## Deploy
Push to GitHub, import in Vercel, add the two `VITE_` env vars.
## Security model
Clients can only SELECT public state. Cards and answers have no read policy; every action (`ask`, `guess`, `skip`...) is a SECURITY DEFINER function that checks the player token and whose turn it is, and scoring happens in SQL. The answer is copied to `game_rounds.answer_reveal` only when the round ends.
## Not yet built
Community decks, seed cards for 5 of 7 categories, turn timer, disconnect/host-transfer (Presence), room expiry.
