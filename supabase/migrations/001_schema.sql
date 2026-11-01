create extension if not exists pgcrypto;
create table decks(id uuid primary key default gen_random_uuid(), name text not null, description text, category text, visibility text default 'public', created_by text, created_at timestamptz default now());
create table cards(id uuid primary key default gen_random_uuid(), deck_id uuid references decks on delete cascade, answer text not null, accepted_answers jsonb default '[]', description text, image_url text, difficulty text default 'easy', hints jsonb default '[]');
create table card_questions(id uuid primary key default gen_random_uuid(), card_id uuid references cards on delete cascade, question text not null, answer text check (answer in ('yes','no','sometimes')));
create table rooms(id uuid primary key default gen_random_uuid(), room_code text unique, host_player_id uuid, status text default 'lobby', total_rounds int, current_round int default 0, current_player_id uuid, selected_categories text[], difficulty text, created_at timestamptz default now());
create table room_players(id uuid primary key default gen_random_uuid(), room_id uuid references rooms on delete cascade, nickname text, player_token text default encode(gen_random_bytes(16),'hex'), score int default 0, join_order int, is_connected bool default true, unique(room_id,nickname));
create table game_rounds(id uuid primary key default gen_random_uuid(), room_id uuid references rooms on delete cascade, round_number int, card_id uuid references cards, category text, prompts jsonb, questions_remaining int default 10, status text default 'active', winner_player_id uuid, answer_reveal text, points int default 0);
create table game_questions(id uuid primary key default gen_random_uuid(), round_id uuid references game_rounds on delete cascade, player_id uuid, question text, answer text, created_at timestamptz default now());
create table game_guesses(id uuid primary key default gen_random_uuid(), round_id uuid references game_rounds on delete cascade, player_id uuid, guess text, is_correct bool, created_at timestamptz default now());

-- RLS: clients may only READ public game state. All writes go through RPCs. cards/card_questions have no policy => hidden.
alter table decks enable row level security; alter table cards enable row level security; alter table card_questions enable row level security;
alter table rooms enable row level security; alter table room_players enable row level security; alter table game_rounds enable row level security;
alter table game_questions enable row level security; alter table game_guesses enable row level security;
create policy r on decks for select using (visibility='public');
create policy r on rooms for select using (true); create policy r on room_players for select using (true);
create policy r on game_rounds for select using (true); create policy r on game_questions for select using (true); create policy r on game_guesses for select using (true);
revoke all on all tables in schema public from anon, authenticated;
grant select on decks, rooms, game_rounds, game_questions, game_guesses to anon, authenticated;
grant select(id,room_id,nickname,score,join_order,is_connected) on room_players to anon, authenticated; -- player_token stays private
alter publication supabase_realtime add table rooms, room_players, game_rounds, game_questions;

create function _host(t text, rid uuid) returns void language plpgsql security definer set search_path=public as $$
begin if not exists(select 1 from rooms r join room_players p on p.id=r.host_player_id where r.id=rid and p.player_token=t) then raise exception 'Only the host can do that'; end if; end $$;

create function _next(rid uuid, cur uuid) returns uuid language sql security definer set search_path=public as $$
select id from room_players where room_id=rid and is_connected order by (join_order <= (select join_order from room_players where id=cur)), join_order limit 1 $$;

create function _turn(t text, rd uuid) returns game_rounds language plpgsql security definer set search_path=public as $$
declare g game_rounds;
begin select * into g from game_rounds where id=rd and status='active';
 if not found then raise exception 'Round is not active'; end if;
 if not exists(select 1 from rooms r join room_players p on p.id=r.current_player_id where r.id=g.room_id and p.player_token=t) then raise exception 'It is not your turn'; end if;
 return g; end $$;

create function _end(rd uuid, w uuid, pts int) returns void language plpgsql security definer set search_path=public as $$
begin
 update game_rounds set status='done', winner_player_id=w, points=pts, answer_reveal=(select answer from cards where id=card_id) where id=rd;
 update room_players set score=score+pts where id=w;
 update rooms set status='round_over', current_player_id=null where id=(select room_id from game_rounds where id=rd);
end $$;

create function _start_round(rid uuid) returns void language plpgsql security definer set search_path=public as $$
declare r rooms; c cards; cat text;
begin select * into r from rooms where id=rid;
 select cd.* into c from cards cd join decks d on d.id=cd.deck_id where d.category=any(r.selected_categories) and (r.difficulty='Mixed' or cd.difficulty=lower(r.difficulty)) and cd.id not in (select card_id from game_rounds where room_id=rid) order by random() limit 1;
 if not found then select cd.* into c from cards cd join decks d on d.id=cd.deck_id where d.category=any(r.selected_categories) order by random() limit 1; end if;
 if not found then raise exception 'No cards available for these categories'; end if;
 select category into cat from decks where id=c.deck_id;
 insert into game_rounds(room_id,round_number,card_id,category,prompts) values(rid,r.current_round+1,c.id,cat,(select jsonb_agg(jsonb_build_object('id',id,'q',question) order by random()) from card_questions where card_id=c.id));
 update rooms set status='playing', current_round=current_round+1, current_player_id=(select id from room_players where room_id=rid order by join_order limit 1) where id=rid;
end $$;
revoke all on function _host(text,uuid), _next(uuid,uuid), _turn(text,uuid), _end(uuid,uuid,int), _start_round(uuid) from public, anon, authenticated;

create function create_room(nick text, rounds int, cats text[], diff text) returns json language plpgsql security definer set search_path=public as $$
declare r rooms; p room_players; code text;
begin
 if rounds not in (5,10,15) or coalesce(array_length(cats,1),0)=0 or length(trim(nick))=0 then raise exception 'Invalid room settings'; end if;
 loop code:=substr(translate(upper(encode(gen_random_bytes(6),'base64')),'+/=IL0O1','XYZABCDE'),1,6); exit when not exists(select 1 from rooms where room_code=code); end loop;
 insert into rooms(room_code,total_rounds,selected_categories,difficulty) values(code,rounds,cats,diff) returning * into r;
 insert into room_players(room_id,nickname,join_order) values(r.id,trim(nick),1) returning * into p;
 update rooms set host_player_id=p.id where id=r.id;
 return json_build_object('room_id',r.id,'code',code,'player_id',p.id,'token',p.player_token); end $$;

create function join_room(rcode text, nick text) returns json language plpgsql security definer set search_path=public as $$
declare r rooms; p room_players;
begin select * into r from rooms where room_code=upper(trim(rcode));
 if not found then raise exception 'Room not found'; end if;
 if r.status<>'lobby' then raise exception 'Game already started'; end if;
 if (select count(*) from room_players where room_id=r.id)>=8 then raise exception 'Room is full'; end if;
 begin insert into room_players(room_id,nickname,join_order) values(r.id,trim(nick),(select coalesce(max(join_order),0)+1 from room_players where room_id=r.id)) returning * into p;
 exception when unique_violation then raise exception 'That nickname is taken in this room'; end;
 return json_build_object('room_id',r.id,'code',r.room_code,'player_id',p.id,'token',p.player_token); end $$;

create function start_game(t text, rid uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _host(t,rid);
 if (select count(*) from room_players where room_id=rid)<2 then raise exception 'Need at least 2 players'; end if;
 if (select status from rooms where id=rid)<>'lobby' then raise exception 'Already started'; end if;
 perform _start_round(rid); end $$;

create function ask(t text, rd uuid, qid uuid) returns void language plpgsql security definer set search_path=public as $$
declare g game_rounds; q card_questions; pid uuid; left_ int;
begin g:=_turn(t,rd);
 select * into q from card_questions where id=qid and card_id=g.card_id;
 if not found then raise exception 'Invalid question'; end if;
 if exists(select 1 from game_questions where round_id=rd and question=q.question) then raise exception 'Already asked'; end if;
 select current_player_id into pid from rooms where id=g.room_id;
 insert into game_questions(round_id,player_id,question,answer) values(rd,pid,q.question,q.answer);
 left_:=g.questions_remaining-1;
 update game_rounds set questions_remaining=left_ where id=rd;
 if left_<=0 or (select count(*) from game_questions where round_id=rd)>=jsonb_array_length(g.prompts) then perform _end(rd,null,0);
 else update rooms set current_player_id=_next(g.room_id,pid) where id=g.room_id; end if; end $$;

create function guess(t text, rd uuid, txt text) returns boolean language plpgsql security definer set search_path=public as $$
declare g game_rounds; c cards; pid uuid; ok bool;
begin g:=_turn(t,rd); select * into c from cards where id=g.card_id; select current_player_id into pid from rooms where id=g.room_id;
 ok:= lower(trim(txt))=lower(trim(c.answer)) or exists(select 1 from jsonb_array_elements_text(c.accepted_answers) a where lower(trim(a))=lower(trim(txt)));
 insert into game_guesses(round_id,player_id,guess,is_correct) values(rd,pid,txt,ok);
 if ok then perform _end(rd,pid,10+g.questions_remaining);
 else update rooms set current_player_id=_next(g.room_id,pid) where id=g.room_id; end if;
 return ok; end $$;

create function skip(t text, rd uuid) returns void language plpgsql security definer set search_path=public as $$
declare g game_rounds;
begin g:=_turn(t,rd); update rooms set current_player_id=_next(g.room_id,current_player_id) where id=g.room_id; end $$;

create function next_round(t text, rid uuid) returns void language plpgsql security definer set search_path=public as $$
declare r rooms;
begin perform _host(t,rid); select * into r from rooms where id=rid;
 if r.status<>'round_over' then raise exception 'Round still in progress'; end if;
 if r.current_round>=r.total_rounds then update rooms set status='finished' where id=rid; else perform _start_round(rid); end if; end $$;

create function play_again(t text, rid uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _host(t,rid); delete from game_rounds where room_id=rid; update room_players set score=0 where room_id=rid; update rooms set status='lobby', current_round=0, current_player_id=null where id=rid; end $$;
grant execute on function create_room, join_room, start_game, ask, guess, skip, next_round, play_again to anon, authenticated;
