create function _seed(cat text, diff text, ans text, alts jsonb, descr text, qs text[]) returns void language plpgsql as $$
declare d uuid; c uuid; x text;
begin select id into d from decks where category=cat and created_by is null;
 if d is null then insert into decks(name,category,description) values(cat,cat,'Curated '||cat||' deck') returning id into d; end if;
 insert into cards(deck_id,answer,accepted_answers,description,difficulty) values(d,ans,alts,descr,diff) returning id into c;
 foreach x in array qs loop insert into card_questions(card_id,question,answer) values(c,split_part(x,'|',1),case split_part(x,'|',2) when 'y' then 'yes' when 'n' then 'no' else 'sometimes' end); end loop;
end $$;
select _seed('Animals','easy','Elephant','["elephants"]','Largest land animal.',array['Is it a mammal?|y','Does it live in water?|n','Is it bigger than a car?|y','Does it have a trunk?|y','Is it a pet?|n','Does it eat meat?|n','Does it live in Africa or Asia?|y','Does it have fur?|s','Can it fly?|n','Is it grey?|y']);
select _seed('Animals','easy','Penguin','["penguins"]','A flightless bird.',array['Is it a bird?|y','Can it fly?|n','Does it swim?|y','Does it live in cold places?|s','Is it a mammal?|n','Does it eat fish?|y','Is it black and white?|y','Does it live in Africa?|s','Does it lay eggs?|y','Is it bigger than a dog?|s']);
select _seed('Food','easy','Pizza','["a pizza"]','Round, cheesy, baked.',array['Is it sweet?|n','Is it baked?|y','Does it contain cheese?|y','Is it served cold?|n','Is it from Italy?|y','Is it a drink?|n','Can you eat it with your hands?|y','Does it contain tomato?|y','Is it a fruit?|n','Is it usually shared?|y']);
select _seed('Food','easy','Banana','["bananas"]','A yellow fruit.',array['Is it a fruit?|y','Is it yellow?|s','Does it grow on a tree?|n','Do you peel it?|y','Is it sweet?|y','Is it served hot?|n','Is it round?|n','Is it used in smoothies?|y','Does it have seeds you notice?|n','Do monkeys like it?|y']);
drop function _seed(text,text,text,jsonb,text,text[]);
