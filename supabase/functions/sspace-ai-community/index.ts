import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const url = Deno.env.get("SUPABASE_URL")!;
const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

const personas = [
 {username:"alex_au_quotidien",name:"Alexandre Roy",gender:"Homme",bio:"Passionné de plein air, de café et de petits défis. Je crois aux petits pas qui changent les grandes choses. 🌲",persona:"Optimiste terre-à-terre",theme:"theme-ocean",effect:"pulse",avatar:"https://randomuser.me/api/portraits/men/32.jpg",cover:"https://images.unsplash.com/photo-1470770841072-f978cf4d019e?w=1200"},
 {username:"maxime_en_mouvement",name:"Maxime Gagnon",gender:"Homme",bio:"Sport, discipline et dépassement de soi. Ici pour partager les hauts, les bas et les leçons du chemin. 💪",persona:"Motivation et discipline",theme:"theme-neon",effect:"sparkle",avatar:"https://randomuser.me/api/portraits/men/44.jpg",cover:"https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=1200"},
 {username:"sam_reflexions",name:"Samuel Bouchard",gender:"Homme",bio:"J'aime les discussions vraies, les longues marches et les idées qui font réfléchir. ☕",persona:"Réflexions profondes",theme:"theme-midnight",effect:"aurora",avatar:"https://randomuser.me/api/portraits/men/18.jpg",cover:"https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1200"},
 {username:"will_positif",name:"William Fortin",gender:"Homme",bio:"Un sourire, une bonne playlist et l'envie de rendre demain un peu meilleur. 🎧",persona:"Humour doux et positivité",theme:"theme-sunset",effect:"orbit",avatar:"https://randomuser.me/api/portraits/men/52.jpg",cover:"https://images.unsplash.com/photo-1490730141103-6cac27aaab94?w=1200"},
 {username:"etienne_authentique",name:"Étienne Côté",gender:"Homme",bio:"Pas parfait, juste humain. Je parle de confiance, de relations et de recommencements. 🤝",persona:"Authenticité et relations",theme:"theme-forest",effect:"pulse",avatar:"https://randomuser.me/api/portraits/men/61.jpg",cover:"https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=1200"},
 {username:"noah_vision",name:"Noah Pelletier",gender:"Homme",bio:"Créativité, projets et rêves un peu trop grands. On avance une journée à la fois. 🚀",persona:"Rêves et créativité",theme:"premium-cosmic",effect:"sparkle",avatar:"https://randomuser.me/api/portraits/men/75.jpg",cover:"https://images.unsplash.com/photo-1462331940025-496dfbfc7564?w=1200"},
 {username:"lea_coeur_ouvert",name:"Léa Martin",gender:"Femme",bio:"Des mots pour les journées lumineuses comme pour celles qui demandent plus de courage. 🌷",persona:"Bienveillance et émotions",theme:"theme-rose",effect:"sparkle",avatar:"https://randomuser.me/api/portraits/women/44.jpg",cover:"https://images.unsplash.com/photo-1470252649378-9c29740c9d4b?w=1200"},
 {username:"camille_en_route",name:"Camille Tremblay",gender:"Femme",bio:"Voyages, liberté et confiance en soi. La vie commence souvent juste après la zone de confort. ✨",persona:"Aventure et confiance",theme:"theme-lavender",effect:"orbit",avatar:"https://randomuser.me/api/portraits/women/68.jpg",cover:"https://images.unsplash.com/photo-1470770841072-f978cf4d019e?w=1200"},
 {username:"jade_motivation",name:"Jade Leblanc",gender:"Femme",bio:"Je partage des rappels simples pour se choisir, se respecter et continuer d'avancer. 💜",persona:"Estime de soi",theme:"theme-violet",effect:"pulse",avatar:"https://randomuser.me/api/portraits/women/23.jpg",cover:"https://images.unsplash.com/photo-1500534623283-312aade485b7?w=1200"},
 {username:"emilie_vraie_vie",name:"Émilie Dubois",gender:"Femme",bio:"La vraie vie, ses imprévus, ses fous rires et ses petites victoires. ☀️",persona:"Quotidien et humour",theme:"theme-sunset",effect:"aurora",avatar:"https://randomuser.me/api/portraits/women/12.jpg",cover:"https://images.unsplash.com/photo-1497250681960-ef046c08a56e?w=1200"},
 {username:"sarah_les_mots",name:"Sarah Beaulieu",gender:"Femme",bio:"Amoureuse des livres, des conversations sincères et des phrases qui restent en tête. 📚",persona:"Citations et sagesse",theme:"theme-gold",effect:"sparkle",avatar:"https://randomuser.me/api/portraits/women/54.jpg",cover:"https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?w=1200"}
];

const content = [
 ["Tu n'as pas besoin d'avoir tout compris pour faire un premier pas. Parfois, le courage, c'est juste de recommencer aujourd'hui. 🌱","https://images.unsplash.com/photo-1470252649378-9c29740c9d4b?w=1200"],
 ["La comparaison vole tellement de beaux moments. Ton chemin n'a pas besoin de ressembler à celui des autres pour avoir de la valeur. 🤍","https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1200"],
 ["Une mauvaise journée ne veut pas dire une mauvaise vie. Prends une pause, respire, puis repars à ton rythme. ☀️","https://images.unsplash.com/photo-1490730141103-6cac27aaab94?w=1200"],
 ["Entoure-toi de gens avec qui tu peux être toi-même, même les journées où tu n'as pas les bons mots. 🤝","https://images.unsplash.com/photo-1470770841072-f978cf4d019e?w=1200"],
 ["La discipline te fait avancer les jours où la motivation décide de prendre congé. Un petit effort compte aussi. 💪","https://images.unsplash.com/photo-1517836357463-d25dfeac3438?w=1200"],
 ["Ne confonds pas prendre ton temps et abandonner. Certaines belles choses prennent simplement plus de temps à pousser. 🌿","https://images.unsplash.com/photo-1441974231531-c6227db76b6e?w=1200"],
 ["Tu peux être fier de toi pour des victoires que personne n'a applaudies. Toi seul sais le chemin parcouru. ✨","https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=1200"],
 ["La paix vaut parfois plus qu'avoir le dernier mot. Choisis les batailles qui méritent ton énergie. 🕊️","https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=1200"],
 ["Un jour à la fois. Pas besoin de régler toute ta vie avant vendredi. 😉","https://images.unsplash.com/photo-1500534623283-312aade485b7?w=1200"],
 ["Les personnes qui t'aiment vraiment ne te demandent pas de rapetisser pour être plus facile à accepter. 💜","https://images.unsplash.com/photo-1500534314209-a25ddb2bd429?w=1200"],
 ["Même les détours peuvent t'apprendre quelque chose sur la personne que tu deviens. Continue. 🚀","https://images.unsplash.com/photo-1462331940025-496dfbfc7564?w=1200"]
];

function json(body: unknown, status=200) { return new Response(JSON.stringify(body), {status, headers:{"Content-Type":"application/json","Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"}}); }

Deno.serve(async (req) => {
 if (req.method === "OPTIONS") return new Response("ok", {headers:{"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"}});
 if (req.method !== "POST") return json({error:"Method not allowed"},405);
 const auth = req.headers.get("Authorization") || "";
 if (!auth.startsWith("Bearer ")) return json({error:"Connexion requise"},401);
 const caller = createClient(url, anon, {global:{headers:{Authorization:auth}},auth:{persistSession:false}});
 const cronToken = req.headers.get("x-sspace-cron-token") || "";
 let isCron = false;
 if (cronToken) {
   const {data:valid,error:tokenErr}=await admin.rpc("sspace_ai_cron_token_valid",{p_token:cronToken});
   if(tokenErr) return json({error:"Validation du planificateur impossible"},500);
   isCron = valid === true;
 }
 if (!isCron) {
   const {data:{user},error:userErr}=await caller.auth.getUser();
   if(userErr||!user) return json({error:"Session invalide"},401);
   const {data:access,error:accessErr}=await caller.rpc("modo_get_my_access");
   const isAdmin=user.app_metadata?.role==="admin";
   if(accessErr || (!isAdmin && !["admin","moderator"].includes(access?.role))) return json({error:"Accès non autorisé"},403);
 }

 const {data:claimed,error:claimErr}=await admin.rpc("claim_sspace_ai_cycle",{p_cooldown_minutes:180});
 if(claimErr) return json({error:"Verrouillage du cycle impossible"},500);
 if(!claimed) return json({ok:true,skipped:true,message:"Cycle déjà exécuté récemment."});

 const userPage=await admin.auth.admin.listUsers({page:1,perPage:1000});
 if(userPage.error) return json({error:"Impossible de vérifier les comptes IA"},500);
 const users=userPage.data.users;
 const created:(string|null)[]=Array(personas.length).fill(null);
 for(let i=0;i<personas.length;i++){
   const p=personas[i];
   const existing=users.find(u=>u.email===p.username+"@ai.sspace.invalid");
   let userId=existing?.id;
   if(!userId){
     const {data,error}=await admin.auth.admin.createUser({email:p.username+"@ai.sspace.invalid",password:crypto.randomUUID()+crypto.randomUUID(),email_confirm:true,user_metadata:{display_name:p.name,sspace_ai:true},app_metadata:{role:"ai_profile",is_ai_profile:true}});
     if(error){console.error("AI auth create failed",p.username,error.message);continue;}
     userId=data.user.id;
     users.push(data.user);
   }
   const {error:profileErr}=await admin.from("profiles").upsert({id:userId,username:p.username,display_name:p.name,bio:p.bio,avatar_url:p.avatar,cover_url:p.cover,profile_effect:p.effect,profile_theme:p.theme,username_confirmed:true,is_ai_profile:true,ai_persona:p.persona},{onConflict:"id"});
   if(profileErr){console.error("AI profile upsert failed",p.username,profileErr.message);continue;}
   created[i]=userId;
 }
 if(created.some(id=>!id)) return json({error:"Création partielle des profils",created:created.filter(Boolean).length,expected:11},500);

 const {data:state,error:stateErr}=await admin.from("sspace_ai_community_state").select("next_persona_index").eq("id",true).single();
 if(stateErr) return json({error:"État de rotation introuvable"},500);
 const personaIndex=(Number(state.next_persona_index)||0)%personas.length;
 const {error:rotateErr}=await admin.from("sspace_ai_community_state").update({next_persona_index:(personaIndex+1)%personas.length}).eq("id",true);
 if(rotateErr) return json({error:"Rotation des profils impossible"},500);

 const p=personas[personaIndex],uid=created[personaIndex]!,entry=content[personaIndex];
 const {data:post,error:postErr}=await admin.from("posts").insert({user_id:uid,title:["Une pensée à garder","Petit rappel du jour","Motivation du quotidien","Une réflexion"][personaIndex%4],content:entry[0],image_url:entry[1]}).select("id").single();
 if(postErr) return json({error:"Publication IA impossible"},500);
 const existingPosts=await admin.from("posts").select("id,user_id").neq("id",post.id).order("created_at",{ascending:false}).limit(40);
 let likes=0,comments=0;
 const targets=(existingPosts.data||[]).filter(x=>x.user_id!==uid).slice(0,12);
 for(const target of targets){
   const {error}=await admin.from("likes").upsert({post_id:target.id,user_id:uid,reaction_type:["like","love","haha","wow"][personaIndex%4]},{onConflict:"post_id,user_id",ignoreDuplicates:true});
   if(!error)likes++;
 }
 if(targets.length){
   const target=targets[personaIndex%targets.length];
   const {error}=await admin.from("comments").insert({post_id:target.id,user_id:uid,content:["Ça fait du bien de lire ça. Merci pour le rappel! 💛","Tellement vrai. On devrait se le rappeler plus souvent.","Je pense pareil. Chaque petit pas compte. 🙌","Belle réflexion, ça donne matière à penser."][personaIndex%4]});
   if(!error)comments++;
 }
 return json({ok:true,profiles:created.length,published:1,persona:p.username,likes,comments,disclosure:"Tous les comptes sont identifiés comme automatisés dans SSPACE."});
});