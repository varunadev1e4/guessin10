create function leave_room(t text, rid uuid) returns void language plpgsql security definer set search_path=public as $$
declare p room_players; r rooms;
begin select * into p from room_players where room_id=rid and player_token=t; if not found then return; end if;
 select * into r from rooms where id=rid;
 if r.status='lobby' then delete from room_players where id=p.id; else update room_players set is_connected=false where id=p.id; end if;
 if not exists(select 1 from room_players where room_id=rid and is_connected) then delete from rooms where id=rid; return; end if;
 if r.host_player_id=p.id then update rooms set host_player_id=(select id from room_players where room_id=rid and is_connected order by join_order limit 1) where id=rid; end if;
 if r.status='playing' and r.current_player_id=p.id then update rooms set current_player_id=_next(rid,p.id) where id=rid; end if;
end $$;
grant execute on function leave_room to anon, authenticated;

create or replace function start_game(t text, rid uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _host(t,rid);
 if (select count(*) from room_players where room_id=rid and is_connected)<2 then raise exception 'Need at least 2 players'; end if;
 if (select status from rooms where id=rid)<>'lobby' then raise exception 'Already started'; end if;
 perform _start_round(rid); end $$;

create or replace function play_again(t text, rid uuid) returns void language plpgsql security definer set search_path=public as $$
begin perform _host(t,rid); delete from game_rounds where room_id=rid; delete from room_players where room_id=rid and not is_connected;
 update room_players set score=0 where room_id=rid; update rooms set status='lobby', current_round=0, current_player_id=null where id=rid; end $$;

create function _seed(cat text, diff text, ans text, alts jsonb, descr text, qs text[]) returns void language plpgsql as $$
declare d uuid; c uuid; x text;
begin select id into d from decks where category=cat and created_by is null limit 1;
 if d is null then insert into decks(name,category,description) values(cat,cat,'Curated '||cat||' deck') returning id into d; end if;
 if exists(select 1 from cards where deck_id=d and answer=ans) then return; end if;
 insert into cards(deck_id,answer,accepted_answers,description,difficulty) values(d,ans,alts,descr,diff) returning id into c;
 foreach x in array qs loop insert into card_questions(card_id,question,answer) values(c,split_part(x,'|',1),case split_part(x,'|',2) when 'y' then 'yes' when 'n' then 'no' else 'sometimes' end); end loop;
end $$;
select _seed('Marvel Characters','easy','Spider-Man','["spiderman","spider man","peter parker"]','The friendly neighborhood hero.',array['Is he a hero?|y','Does he wear a mask?|y','Can he fly?|n','Did he get his powers from a spider?|y','Is he an Avenger?|y','Is he a billionaire?|n','Does he live in New York City?|y','Does he shoot webs?|y','Is he an alien?|n','Does he wear red?|y']);
select _seed('Marvel Characters','easy','Iron Man','["ironman","tony stark"]','Genius in a suit of armor.',array['Is he a hero?|y','Does he wear a suit of armor?|y','Can he fly?|y','Was he born with superpowers?|n','Is he a billionaire?|y','Is he an Avenger?|y','Is he from another planet?|n','Does he use a hammer?|n','Does he wear red and gold?|y','Is he a genius inventor?|y']);
select _seed('Marvel Characters','easy','Captain America','["steve rogers","cap"]','The super-soldier with a shield.',array['Is he a hero?|y','Does he carry a shield?|y','Can he fly?|n','Was he a soldier?|y','Is he an Avenger?|y','Is he from another planet?|n','Does he wear a mask?|s','Does his costume have stars?|y','Was he frozen in ice?|y','Is he a billionaire?|n']);
select _seed('Marvel Characters','easy','Thor','["thor odinson","god of thunder"]','God of Thunder.',array['Is he a hero?|y','Is he from another planet?|y','Does he use a hammer?|y','Can he control lightning?|y','Is he an Avenger?|y','Is he a god?|y','Does he wear a mask?|n','Does he have a cape?|y','Is his brother a villain?|y','Is he a billionaire?|n']);
select _seed('Marvel Characters','medium','Black Panther','["t''challa","tchalla","the black panther"]','King of Wakanda.',array['Is he a hero?|y','Is he a king?|y','Is his suit made of vibranium?|y','Is he from Africa?|y','Can he fly?|n','Is he an Avenger?|y','Does he wear a mask?|y','Is he from another planet?|n','Does he have claws?|y','Is he rich?|y']);
select _seed('Marvel Characters','medium','Thanos','["the mad titan"]','Wants all the Infinity Stones.',array['Is he a hero?|n','Is he from another planet?|y','Does he want the Infinity Stones?|y','Is he an Avenger?|n','Is he purple?|y','Is he very strong?|y','Does he wear a mask?|n','Is he from Earth?|n','Can he fly?|n','Did he make half of all life vanish?|y']);
select _seed('DC Characters','easy','Batman','["bruce wayne","the batman"]','The Dark Knight of Gotham.',array['Is he a hero?|y','Does he have superpowers?|n','Can he fly?|n','Does he wear a mask?|y','Is he a billionaire?|y','Is he from another planet?|n','Does he live in Gotham City?|y','Does he wear a cape?|y','Is he in the Justice League?|y','Does he use gadgets?|y']);
select _seed('DC Characters','easy','Superman','["clark kent","kal-el","kal el"]','The Man of Steel.',array['Is he a hero?|y','Can he fly?|y','Is he from another planet?|y','Does he wear a mask?|n','Does he wear a cape?|y','Is he weak to kryptonite?|y','Is he a billionaire?|n','Does he live in Gotham City?|n','Does he have a logo on his chest?|y','Is he in the Justice League?|y']);
select _seed('DC Characters','easy','Wonder Woman','["diana prince","diana"]','Amazon warrior princess.',array['Is she a hero?|y','Is she from Earth?|s','Does she use a lasso?|y','Can she fly?|s','Does she wear a mask?|n','Is she an Amazon warrior?|y','Is she in the Justice League?|y','Does she use a sword and shield?|y','Is she a billionaire?|n','Is she from Themyscira?|y']);
select _seed('DC Characters','easy','The Flash','["flash","barry allen"]','The fastest man alive.',array['Is he a hero?|y','Is he super fast?|y','Can he fly?|n','Does he wear a mask?|s','Does he wear red?|y','Is he a billionaire?|n','Is he from another planet?|n','Is he in the Justice League?|y','Does he use a weapon?|n','Is there a lightning bolt on his suit?|y']);
select _seed('DC Characters','medium','Joker','["the joker"]','The Clown Prince of Crime.',array['Is he a hero?|n','Is he a criminal?|y','Does he have superpowers?|n','Is he an enemy of Batman?|y','Does he wear a mask?|n','Does he have green hair?|y','Does he live in Gotham City?|y','Is he from another planet?|n','Is he in the Justice League?|n','Does he use pranks in his crimes?|y']);
select _seed('DC Characters','medium','Aquaman','["arthur curry"]','King of Atlantis.',array['Is he a hero?|y','Can he breathe underwater?|y','Is he a king?|y','Can he talk to sea animals?|y','Does he wear a mask?|n','Does he use a trident?|y','Is he from another planet?|n','Is he in the Justice League?|y','Does he live in Gotham City?|n','Is he a billionaire?|n']);
drop function _seed(text,text,text,jsonb,text,text[]);
select d.category, count(*) as cards from cards c join decks d on d.id=c.deck_id group by 1 order by 1;
