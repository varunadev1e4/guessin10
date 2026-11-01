import { useEffect, useState, useCallback } from 'react'
import { supabase } from './supabase'

const CATS = ['Animals', 'Countries and Landmarks', 'Science and Space', 'Dinosaurs', 'Food', 'Sports', 'General Knowledge', 'Marvel Characters', 'DC Characters']
const AV = ['🦊', '🐼', '🐸', '🦁', '🐙', '🦄', '🐯', '🐧']
const store = { get: () => JSON.parse(localStorage.getItem('gi10') || 'null'), set: v => localStorage.setItem('gi10', JSON.stringify(v)), clear: () => localStorage.removeItem('gi10') }
const rpc = async (fn, args) => { const { data, error } = await supabase.rpc(fn, args); if (error) throw new Error(error.message); return data }
const link = code => `${location.origin}/?join=${code}`

function useRoom(id) {
  const [s, set] = useState({})
  const load = useCallback(async () => {
    const [r, p, g] = await Promise.all([
      supabase.from('rooms').select('*').eq('id', id).single(),
      supabase.from('room_players').select('id,nickname,score,join_order,is_connected').eq('room_id', id).order('join_order'),
      supabase.from('game_rounds').select('*').eq('room_id', id).order('round_number')])
    const round = g.data?.at(-1)
    const qs = round ? (await supabase.from('game_questions').select('*').eq('round_id', round.id).order('created_at')).data : []
    set({ loaded: true, room: r.data, players: p.data || [], rounds: g.data || [], round, qs: qs || [] })
  }, [id])
  useEffect(() => {
    load()
    const ch = supabase.channel('room-' + id)
    ;['rooms', 'room_players', 'game_rounds', 'game_questions'].forEach(t => ch.on('postgres_changes', { event: '*', schema: 'public', table: t }, load))
    ch.subscribe()
    return () => { supabase.removeChannel(ch) }
  }, [id, load])
  return s
}

export default function App() {
  const [view, setView] = useState(() => store.get() ? 'room' : new URLSearchParams(location.search).get('join') ? 'join' : 'home')
  const [err, setErr] = useState('')
  const run = async fn => { setErr(''); try { await fn() } catch (e) { setErr(e.message) } }
  const enter = d => { store.set(d); history.replaceState({}, '', '/'); setView('room') }
  const leave = async () => { const s = store.get(); if (s) { try { await rpc('leave_room', { t: s.token, rid: s.room_id }) } catch { /* room may be gone */ } } store.clear(); setView('home') }
  const back = () => { history.replaceState({}, '', '/'); setView('home') }
  return (
    <div className="max-w-5xl mx-auto px-4 py-6">
      <header className="flex items-center justify-between mb-6">
        <button onClick={() => view !== 'room' && setView('home')} className="text-3xl font-bold tracking-tight">GUESS <span className="text-sun">IN 10</span></button>
        {view === 'room' && <button className="chip" onClick={leave}>Leave room</button>}
      </header>
      {err && <div role="alert" className="paper !bg-pop !text-white px-4 py-3 mb-4 font-semibold" onClick={() => setErr('')}>{err}</div>}
      {view === 'home' && <Home go={setView} />}
      {view === 'create' && <Create run={run} enter={enter} back={back} />}
      {view === 'join' && <Join run={run} enter={enter} back={back} />}
      {view === 'room' && store.get() && <Room ses={store.get()} run={run} leave={leave} />}
    </div>)
}

function Home({ go }) {
  return (<div className="grid gap-8">
    <section className="grid md:grid-cols-2 gap-8 items-center py-6">
      <div>
        <h1 className="text-5xl md:text-6xl font-bold leading-tight">One mystery card. Ten questions. First to name it wins.</h1>
        <p className="mt-4 text-lg text-white/80">Take turns asking yes/no questions, then risk a guess. The fewer questions you use, the more points you score.</p>
        <div className="flex gap-3 mt-6 flex-wrap"><button className="btn" onClick={() => go('create')}>Create room</button>
          <button className="btn !bg-white" onClick={() => go('join')}>Join room</button></div>
      </div>
      <div className="paper flip mx-auto w-64 h-80 grid place-items-center rotate-3 !bg-pop"><span className="text-9xl font-bold text-white drop-shadow-[4px_4px_0_#000]">?</span></div>
    </section>
    <section className="grid sm:grid-cols-3 gap-4">
      {[['Ask', 'On your turn, pick a question. Everyone sees the answer.'], ['Guess', 'One guess per turn. A wrong guess passes the turn.'], ['Score', 'Correct guess = 10 points + 1 per unused question.']].map(([t, d]) =>
        <div key={t} className="paper p-4"><h3 className="text-xl font-bold">{t}</h3><p>{d}</p></div>)}
    </section>
    <section><h2 className="text-2xl font-bold mb-3">Decks</h2><div className="flex flex-wrap gap-2">{CATS.map(c => <span key={c} className="chip">{c}</span>)}</div></section>
  </div>)
}

function Create({ run, enter, back }) {
  const [nick, setNick] = useState(''), [rounds, setRounds] = useState(5), [cats, setCats] = useState(['Animals']), [diff, setDiff] = useState('Mixed')
  const toggle = c => setCats(x => x.includes(c) ? x.filter(i => i !== c) : [...x, c])
  const go = e => { e.preventDefault(); run(async () => enter(await rpc('create_room', { nick, rounds, cats, diff }))) }
  return (<form onSubmit={go} className="paper p-6 grid gap-5 max-w-xl mx-auto">
    <button type="button" className="chip w-fit" onClick={back}>← Back</button>
    <h2 className="text-3xl font-bold">Create a room</h2>
    <input className="inp" placeholder="Your nickname" maxLength={16} value={nick} onChange={e => setNick(e.target.value)} required />
    <div><p className="font-semibold mb-2">Rounds</p><div className="flex gap-2">{[5, 10, 15].map(n => <button type="button" key={n} className="chip" aria-pressed={rounds === n} onClick={() => setRounds(n)}>{n}</button>)}</div></div>
    <div><p className="font-semibold mb-2">Categories</p><div className="flex flex-wrap gap-2">{CATS.map(c => <button type="button" key={c} className="chip" aria-pressed={cats.includes(c)} onClick={() => toggle(c)}>{c}</button>)}</div></div>
    <div><p className="font-semibold mb-2">Difficulty</p><div className="flex gap-2 flex-wrap">{['Easy', 'Medium', 'Hard', 'Mixed'].map(d => <button type="button" key={d} className="chip" aria-pressed={diff === d} onClick={() => setDiff(d)}>{d}</button>)}</div></div>
    <button className="btn" disabled={!cats.length}>Create room</button>
  </form>)
}

function Join({ run, enter, back }) {
  const [code, setCode] = useState(new URLSearchParams(location.search).get('join') || ''), [nick, setNick] = useState('')
  const go = e => { e.preventDefault(); run(async () => enter(await rpc('join_room', { rcode: code, nick }))) }
  return (<form onSubmit={go} className="paper p-6 grid gap-4 max-w-md mx-auto">
    <button type="button" className="chip w-fit" onClick={back}>← Back</button>
    <h2 className="text-3xl font-bold">Join a room</h2>
    <input className="inp uppercase tracking-widest text-center text-2xl" placeholder="ROOM CODE" maxLength={6} value={code} onChange={e => setCode(e.target.value)} required />
    <input className="inp" placeholder="Your nickname" maxLength={16} value={nick} onChange={e => setNick(e.target.value)} required />
    <button className="btn">Join room</button>
  </form>)
}

function Board({ players, room, me }) {
  return (<ul className="grid gap-2 content-start">{players.map((p, i) => !p.is_connected ? null : (
    <li key={p.id} className={`paper !shadow-[3px_3px_0_#000] px-3 py-2 flex items-center gap-2 ${room.current_player_id === p.id ? '!bg-sun pulse' : ''}`}>
      <span className="text-2xl">{AV[i % 8]}</span><span className="font-semibold flex-1 truncate">{p.nickname}{p.id === me && ' (you)'}{p.id === room.host_player_id && ' 👑'}</span>
      <span className="font-bold">{p.score}</span></li>))}</ul>)
}

const badge = a => ({ yes: 'bg-mint', no: 'bg-pop text-white', sometimes: 'bg-sun' }[a])
function History({ qs, players }) {
  return (<ul className="grid gap-2">{qs.length === 0 && <li className="opacity-60">No questions yet.</li>}{qs.map(q => (
    <li key={q.id} className="flex items-center gap-2"><span className="flex-1"><b>{players.find(p => p.id === q.player_id)?.nickname}:</b> {q.question}</span>
      <span className={`px-3 rounded-full border-2 border-black font-bold capitalize text-ink ${badge(q.answer)}`}>{q.answer}</span></li>))}</ul>)
}

function Room({ ses, run, leave }) {
  const { loaded, room, players, round, rounds, qs } = useRoom(ses.room_id)
  const [guess, setGuess] = useState('')
  if (!room) return loaded ? <div className="paper p-6 max-w-md mx-auto grid gap-3"><p className="font-bold">This room no longer exists.</p><button className="btn" onClick={leave}>Back to home</button></div> : <p>Loading…</p>
  const me = ses.player_id, myTurn = room.current_player_id === me, host = room.host_player_id === me
  const name = id => players.find(p => p.id === id)?.nickname
  const T = ses.token

  if (room.status === 'lobby') return (<div className="grid md:grid-cols-[1fr_320px] gap-6">
    <div className="paper p-6 grid gap-4">
      <p>Room code</p><p className="text-6xl font-bold tracking-widest">{room.room_code}</p>
      <button className="chip w-fit" onClick={() => navigator.clipboard.writeText(link(room.room_code))}>Copy invite link</button>
      <p>{room.total_rounds} rounds · {room.difficulty} · {room.selected_categories.join(', ')}</p>
      {host ? <button className="btn" disabled={players.length < 2} onClick={() => run(() => rpc('start_game', { t: T, rid: room.id }))}>{players.length < 2 ? 'Waiting for another player…' : 'Start game'}</button>
        : <p className="font-semibold">Waiting for the host to start…</p>}
    </div><Board players={players} room={room} me={me} /></div>)

  if (room.status === 'finished') {
    const rank = [...players].sort((a, b) => b.score - a.score)
    return (<div className="paper p-6 grid gap-4 max-w-2xl mx-auto">
      <h2 className="text-4xl font-bold">🏆 {rank[0]?.nickname} wins!</h2>
      {rank.map((p, i) => <div key={p.id} className="flex justify-between gap-2 border-b-2 border-ink/10 py-1"><span>{i + 1}. {AV[players.indexOf(p) % 8]} {p.nickname}</span>
        <span className="text-sm opacity-70 flex-1 text-right">{rounds.filter(r => r.winner_player_id === p.id).map(r => `R${r.round_number}: +${r.points}`).join('  ')}</span><b>{p.score}</b></div>)}
      <div className="flex gap-3">{host && <button className="btn" onClick={() => run(() => rpc('play_again', { t: T, rid: room.id }))}>Play again</button>}<button className="btn !bg-white" onClick={leave}>Return home</button></div></div>)
  }

  if (!round) return <p>Loading round…</p>
  const asked = qs.map(q => q.question), prompts = (round.prompts || []).filter(p => !asked.includes(p.q))
  const over = room.status === 'round_over'
  return (<div className="grid md:grid-cols-[1fr_300px] gap-6">
    <div className="grid gap-4 content-start">
      <div className="flex flex-wrap gap-2 items-center"><span className="chip">Round {room.current_round}/{room.total_rounds}</span><span className="chip">{round.category}</span>
        <span className="ml-auto flex gap-1" aria-label={`${round.questions_remaining} questions left`}>{Array.from({ length: 10 }, (_, i) => <i key={i} className={`w-3 h-3 rounded-full border-2 border-white ${i < round.questions_remaining ? 'bg-sun' : 'bg-transparent'}`} />)}</span></div>
      <div className="paper p-6 text-center">
        {over ? <div className="flip"><p>{round.winner_player_id ? `${name(round.winner_player_id)} got it! +${round.points} pts` : 'No one guessed it. 0 points'}</p><p className="text-5xl font-bold my-2">{round.answer_reveal}</p></div>
          : <><div className="text-7xl font-bold text-pop">?</div><p className={`font-semibold mt-2 ${myTurn ? 'text-pop' : ''}`}>{myTurn ? 'Your turn!' : `${name(room.current_player_id)}'s turn`}</p></>}
      </div>
      {!over && <div className="paper p-4 grid gap-3">
        <p className="font-bold">Ask a question</p>
        <div className="flex flex-wrap gap-2">{prompts.map(p => <button key={p.id} className="chip" disabled={!myTurn} onClick={() => run(() => rpc('ask', { t: T, rd: round.id, qid: p.id }))}>{p.q}</button>)}</div>
        <form className="flex gap-2" onSubmit={e => { e.preventDefault(); run(async () => { await rpc('guess', { t: T, rd: round.id, txt: guess }); setGuess('') }) }}>
          <input className="inp" placeholder="Make a guess…" value={guess} onChange={e => setGuess(e.target.value)} disabled={!myTurn} />
          <button className="btn" disabled={!myTurn || !guess.trim()}>Guess</button></form>
        <button className="chip w-fit" disabled={!myTurn} onClick={() => run(() => rpc('skip', { t: T, rd: round.id }))}>Skip turn</button>
      </div>}
      <div className="paper p-4"><p className="font-bold mb-2">Question history</p><History qs={qs} players={players} /></div>
      {over && host && <button className="btn" onClick={() => run(() => rpc('next_round', { t: T, rid: room.id }))}>{room.current_round >= room.total_rounds ? 'See final results' : 'Next round'}</button>}
    </div>
    <Board players={players} room={room} me={me} />
  </div>)
}
