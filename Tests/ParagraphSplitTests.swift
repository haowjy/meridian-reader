import AVFoundation
import SwiftData
import XCTest
@testable import Reader

/// Giant paragraphs split for display + navigation + audio (layout v3, 2026-09-25).
/// Real text: The Forgotten (royalroad 178276), "Prologue / Chapter One: Gunner".
final class ParagraphSplitTests: XCTestCase {
    /// `<div class="chapter-inner chapter-content">` of the chapter page (86 `<p>`, with
    /// `<em>`, `<span>`, `<br>`, `&nbsp;`), fetched 2026-09-25.
    static let chapterHTML = #"""
<p class="cnM3Y2MyOTE4MGQxNjQyMWVhOTQyZDc3NjI3ZDI0ZDBi">The government has canisters of smallpox hidden away in research facilities. They claim it’s for research purposes only, but I’m not so sure. This is my nightmare, and you’re welcome to come along for the ride, just… watch your step.</p>
<p class="cnMyNmJhM2E2YTA1ZDQ3MjNiN2ExOWE0ZDRkZmU4Nzc4">-Gunner</p>
<p class="cnM4NjZiNGQzMWMwYzQ0ODNiMTUzY2ZjMzM5YzViMmEy">&nbsp;</p>
<p class="cnNlOWQ1NTM0YTFmZDQ3NDc5OTU3NWEyNGE4OTFjNzg4">&nbsp;</p>
<p class="cnM3NGQ3MWI2MjhhOTQ3MjY5ZTYzMTUyMWZmZGUxMzJk">&nbsp;</p>
<p class="cnMyYjE1MTlkNWQ5YzQ0NTdiNTMxYTliOGViOGI4MGI3">&nbsp;</p>
<p class="cnM0OTM3MjdkYzcwODQ2NTY5Yjg4MjYzZDdiOWY1MWFm">&nbsp;</p>
<p class="cnNmMzRjOGE2MjcwMzRkNjk4ZDk5MDkzZDMxOTQ5NDg3">&nbsp;</p>
<p class="cnNiZTBiZTI0OGJiMzRkOTlhYmE1ZmVjMjgyMzk1M2Ew">&nbsp;</p>
<p class="cnM3OTVhMzlhZGI3NDQ2ODY5YzQzNTY2NzNlZTg2OWUy">&nbsp;</p>
<p class="cnMzNmQxMmZjNzYwMDQwM2JiYmYyNjZlNjM5ZTNiNjQ1">&nbsp;</p>
<p class="cnM2MTZjOGY4NmM4YzQzMGVhYzE3YzZkODM1MmFhOWFk">&nbsp;</p>
<p class="cnM1ZTQwZmVlNWNkMzRhY2I4YWM0MjBkYmVmY2RkYzUy">&nbsp;</p>
<p class="cnM5ZjdjOWJhMDUyYjRjYWZiMjZkZDI1ZTExNzQxNjY2">&nbsp;</p>
<p class="cnM5NTdmZWRhNjRjMTQxY2NiYjkyZTM2ZTEwNmM1Y2Y5">&nbsp;</p>
<p class="cnM1NzA2YTE3ODk3NzRjNDRiZjY1OTM0ODkzNDEyMGEw">&nbsp;</p>
<p class="cnNiYTBjNDc0NTkxNDQ0M2M4YThmZjhmMmQzOTFjZDA3">&nbsp;</p>
<p class="cnMxMzhjOGZkMTcwZDQwNWFhOGIwOTI4ZDA3MTM4NmFi">Prologue</p>
<p class="cnMyMzE3MTg2ZTcxMzRmNGM5NWViNGZkZTJhNDAxMmUw">&nbsp;</p>
<p class="cnMwMjYyZjQ5NTBkNzQ2MThhZjU4NDVjZDkxZGY4ZDgw">&nbsp;</p>
<p class="cnNmNzM0Yjc2YjM4MjQxMjRiNzY3NDM2Y2ZhZDJjMTgy">WHAT ONCE WAS ORLANDO, FLORIDA, 2240</p>
<p class="cnM4NDU5YTk3NjBjZjRiM2I4ZTBkMDUyMDUwNjlmMWM2">Okay, I’m gonna give you a bit of a rundown of the state of the, well, states. My parents gave me the occasional history lesson and now it's my turn to pass that knowledge on to you. After the Russian/Ukrainian war ended about 2.5 hundred years ago, -nobody can give me an exact year, answers vary, but the most common is 2031- people became restless. Everyone had thought it would be WWIII, especially when Britain joined the war. Following a threat from a Russian scientist, saying they would release bombs containing the virus Smallpox, announcing that they had evolved it to the point that it could wipe out the whole population, people freaked out, remembering the recent pandemic of COVID-19. The most out-of-stock thing people had trouble buying was toilet paper. Superstores and supermarkets were swamped. There were hundreds of people rushing into stores to buy toilet paper and canned food, -is that just food in a can? - it lasted longer like that apparently. When the war ended, again, no specific date, the world was restless. Much of Asia and Europe had been destroyed, only small, nondescript towns staying afloat. Other countries had civil unrest, leading to civil wars. The president by the end was no longer Trump, instead, it was Ian Ericcson-Sprucefeld. He decided to prevent civil unrest, and the Castra system was born. A long dead language, called Latin, was the basis for all the Castra names. Castra means camp, because you are sent to camps based on your skill. This isn't like any super nitty gritty camp, down in the dirt; it's just the name used for the different groups. Each Castra was named after the type of jobs necessary to keep a civilization afloat. The first group, Scienta, or knowledge, consists of jobs in departments such as healthcare, –nurse, doctor, etc- technology, -programmer, civil engineer, etc- and business –accountant, business admin, etc-. The next Castra, Arte, or skill, has jobs such as construction, -site formation, structural engineering, etc- and agriculture, -farming, etc- Castra number three, Entrepreneur, which is the same in both languages, includes things such as entrepreneur, -startup founder, business owner, etc- and business consultant -. Second to last, Artium, or arts with jobs such as performing arts, -actings, vocals, instruments- creative arts, -art, writing, etc-. Finally, Liberandum, or rescue, jobs such as search and rescue -though it’s not as necessary with the organized Castras, they’re more backup for other rescue services, paramedics, fire, and police.</p>
<p class="cnNiOWRlMWUwZDcyZTQyYzE4MmVjNDE5N2Q5M2Y1YTI3">At first, people didn't like the rules. There were too many restrictions, not enough freedom. Some individuals would skip out on their tests, refusing to become part the “New America”.&nbsp;&nbsp; President I. Ericcson-Sprucefeld, said at a press conference, much lacking in actual press, that, “the government has a very powerful weapon in its grasp that, if needed, would be unleashed on the entire population of the U.S.A., no matter how many people are involved.” This shut people up real fast, those involved not wanting their families to get hurt. Once every one of age was tested, underage children would stay with both parents, alternating weeks, until Testing Day.&nbsp; Every year, children at the age of 10 and 16 were tested. For 10-year-olds, they would get tested, just see what they have a gift for. Teachers and parents would use the results from the test, along with the child’s interests, to put more focus on the prominent gifts. Then at 16, they were tested a little more intensely, these tests defining what they should and shouldn't do. The teen would then come back out to the central room and announce the Castra of their choice. Their choice may not reflect their test results; it may, but sometimes they choose based off personal interests. These new Conscribes, or recruits, would pack up their belongings, have a three-day period to say goodbye and then they move to their new Castra.</p>
<p class="cnMzMmRkMzdkMjdmMjQ0MDhhMzZmOGZhMDU3ZDliZTdk">&nbsp;</p>
<p class="cnMxMzE3ZDZkNGE4OTQ5M2Y5MDU4YjdiNDIyMTcyMWJm">&nbsp;</p>
<p class="cnNiMGE5NjI2NjQzYjRkZDk4MzQxZjI2NzhlMDQxNmQ4">&nbsp;</p>
<p class="cnNkYzhmYzVlN2RiYzRlMmNiZGUwMTVmNDFhOGQxZWEw">&nbsp;</p>
<p class="cnMwZjU4Mjk1ZTI2ODRlY2U4NzBmMDg5NTViODJmMWYw">&nbsp;</p>
<p class="cnMwOTQ1NDY2MTk4MTQwYzA4MDhiMTY0N2Y0MzNiYjUx">&nbsp;</p>
<p class="cnNmZTZjMThiZjI1NzQxYjA4MTcyYmI0MzAwN2EzMjJi">&nbsp;</p>
<p class="cnM1MGI5YWI1ZGJkNzQ1MTNhNzQ5YzNlY2M0YjJlODYz">&nbsp;</p>
<p class="cnM1ZTYzYTZkY2Y3YzRhMDY4NTkyMzFkZTM3NTllMjRm">Chapter One</p>
<p class="cnMyYzMzODJhNTMzMDRjYmY4YmI0MmU1NGRmMDAzZWMz">-Gunner-</p>
<p class="cnMyZTNiZTNhZjBjZDQ2MTA5MTczYWE0NzY2ZTU4M2Nk">&nbsp;</p>
<p class="cnNmMTY4YjVjNzJkNTRkN2I4MDk1ZWYyYjA3ZGY2MDQw">&nbsp;</p>
<p class="cnMzODQ0MzZlYWJjNTRlNjBiNjI5ZWRlMmNkYTFkZTU2">ARTE CASTRA, WHAT ONCE WAS ORLANDO, FLORIDA, 2240</p>
<p class="cnNlMmRiNGJkMWM5NTRkNTZhYTUxY2Q0MjAzNTQyYmE5">“Gunner, we need you to listen closely. We know about how you have attributes from all the Castras. This can be a problem in the future because it can be hard to fit in. But it can also be hard because some “special skills” might develop out of this genetic anomaly,” My father had said to me, a grave tone hidden in his voice. I stared at him, confused.</p>
<p class="cnM4MmI0NWVhYjA0OTRkNGE4M2YzZTRiNDMyNThiYzg4">“Skills?” I had asked. My mother looked at me with a serious expression on her face.</p>
<p class="cnNmOGU3MGIyZmYwMDRiYjdhOGRmZjE1ZGI0M2VlNjRm">“This happens very little due to your genes. You should have two main job interests, one from the same Castra as your father, and one from the same Castra as your mother. Something odd about your genes changing that code, making your genetic code hold all the Castras instead. Because you have these genetic malformations, your DNA mutates, causing special abilities you’ve probably only read about in books.” My father answered. My only reaction had been a blank stare, horror eating away at my insides.</p>
<p class="cnNiMTFjYTE4YTUwMDQyZGNiZTYyYjI4NGU3NmE5ZmRl">&nbsp;</p>
<p class="cnMyMWFlNjAyNTFhMzQ4NmY4MzljNjBkYmZjMTliMzQ2">“Grace!” I yell, pounding on the bathroom door, “I need to get ready!” I continue to pound on the door, the hits vibrating into the doorframe. Worry gnaws at my gut, knowing that if she doesn't hurry up, I'll be late. Today, finally, is Choosing Day. I have my test in just over an hour and I'm nervous, <em>very </em>nervous. Grace finishes in the bathroom and I rush in before she can decide her curls aren’t sitting <em>just </em>right.</p>
<p class="cnMxZjRmZWQwNmM2YzQwN2U4OGFmZjA1ODI3ZTlkYzI4">I'm quickly finishing up when my mother decides it's her turn to pound on the door. “Gunner, we’re going to be late!” Her shadow moves under the door. “Hurry up.” Panic spikes in my stomach, little daggers that want to cut me apart. I shut off the faucet, slick back my hair one more time with my wet hands and run out the door, dragging my hands along a hanging towel on my way out of the bathroom. My socks slip along the hardwood floors, and I snag my leather jacket off the dining table chair that I sat in for breakfast. Nobody cares if you dress nicely, just wear clothes. Shoving my feet into my shoes, I hop out the door and head to our pickup truck. No, don't imagine those old, rusted out pickup trucks from the 21st century. Think, sleek, rounded edges with bright headlights. Sensors open the doors, DNA activated. The wheels? There aren’t any. It floats over the driveway, using the minerals in the earth to push off the ground. It must be held up on rubber blocks when off, so it doesn't scrape on the ground. I run across the driveway, press my thumb against the scanner pad, yank open my door, and scream.</p><span class="cmMxZDVhNDUyNDNhMzQzMWI5NGM1NGI0MzIwMDk2OGUx"><br>Stolen content warning: this tale belongs on Royal Road. Report any occurrences elsewhere.<br></span>
<p class="cnNkOGViMGI5Mzk4NjRiM2JiNGIyNjdjYThiZjYxN2Uy">&nbsp;</p>
<p class="cnM4M2JlYWU2Nzg0YzQwZWQ5OGY5ZWU2NzA0NGI3OTdm">Grace giggles. “Haha. Gotchu.” She leaps back as I feel my face morph into anger, nearly hitting her head on the ceiling of the truck. I hop in and simmer in my corner of the truck. I'm sure steam is funneling out of my ears. Or smoke, maybe my hair is on fire. I pat the top of my head. Nope, no fire. Grace snorts.</p>
<p class="cnM2OWQ3YjAwMTlhYzRkMjU5ZThiMDBlZTJlYjZiZjgw">“What are you, a monkey? Are you gonna rub your belly too?” I raise my hand, and she scurries back. Well, as much as one can scurry in the back seat of a truck. I scowl, throwing my hand up in the air as though I’m gonna slap her. Grace flinches, shrinking back into the door.</p>
<p class="cnNjYTZjMTg5YTMxZDQ0OTFiNzNmZjJiNmE5ZTU2MGZk">My mom turns around, eyebrow reaching for her hairline. Dad looks at her, then back at the road. “Can you guys settle down? Gunner, I know you’re nervous but taking it out on your sister does not solve the problem.” I sigh, slumping back into my seat. She's right, I shouldn't be taking my anxiety out on Grace.</p>
<p class="cnMyYzkzYTM2NjhhNDRiMDQ5ZjI3MWM1OThmMjEzMWMx">&nbsp;</p>
<p class="cnNlYzY3OWEzZWMzZDQ2MDc4NmRlODNmZjljNDljMWJh">“Please say goodbye to your families and move to the correct line on the other side of the room. Please say goodb-”</p>
<p class="cnM4YWYwNzZlNTc4NzQxMWVhZDk5YmIyYTAyNzQ5YmI2">“Mom! Please don't make me go! I'm already doing well in your Castra. Arte is where I belong!” I'm pleading, begging for someone to hear me. I don't want to leave. Those skills my parents spoke to me about, they’re freaking me out. I don't want to be a lab rat!</p>
<p class="cnM2ZDMyZDFhZGQwOTQ3ZWVhMmZlNTQyYTMyMGZjOTRl">“Gunner, you need to go before they pull you away. We love you.” Dad says this, sounding stern, but his eyes are sad. He hugs me, and mum joins him. Grace stands back, looking grumpy and annoyed. We make eye contact, and she frowns and looks away. I step out of the hug and turn to Grace. Stepping forward, she turns her head back, looking at me.</p>
<p class="cnM1ZDY2N2JjNTk1MTQ2NmU4ODI0ZTczMGY2MThhMzc4">“Grace.” I say softly.</p>
<p class="cnNjM2I2Y2RlOTdkNDQ1OWViNzdiY2JlNGE0ODE0Mjdj">“Shut up.” She sniffs and hugs me. I squeeze her tight, “don't go.” she whispers, “I don't want you to go.”</p>
<p class="cnNhNDY4OTZkNmNiNTQ0ODBiMjEyYTFiMjU5ZmRlZDVk">“I don't want to go either, but I have to.” I let go and crouch down so I can see her at eye level. “I’ll come back, I promise.” I stand up, turning to my parents one last time. I know I probably won’t be coming back, but Grace needs comfort right now, not harsh reality.</p>
<p class="cnM3Y2NkYTJhYjM1NjQxM2NiMTY2OGQ2MmEyODAzMzgx">“Remember what I told you.” Dad says. I nod, turn and step away, knowing this may be the last time I ever see or hear them. I walk away, forcing my way through the crowd of people packed into the small room.</p>
<p class="cnMzMzA5YWRkZTc4YTQ4NmY4YTE2ZjUxMjdiNTk2ZjY2">“Hi!” A girl jumps in front of me, blocking my path, “I’m Aza, short for Azaline. Are you here for testing too?” She looks way too excited for someone being pulled away from their family.</p>
<p class="cnNjMWVkNDI4NWI4YjQzZjM4M2IyNWFiZGU4NDg0MDA5">“I-”</p>
<p class="cnNhNTc0NTc4MDMyYzRiYzA4M2Y4YzdkNmZiNWIwZTMz">“Of course you are! Why else would you be here?” She grins and grabs my hand.</p>
<p class="cnM2MjNlOWVhMTZlYTQ1NWQ4N2E2OWQ1ODJjOWQwMmJm">“To see my girlfriend off?” her face falls and she drops my hand.</p>
<p class="cnM2NzMxMzk4N2MwZTQwYzBhNmQ4NWNmMzQxZDU4MzYz">“Oh. Sorry.”</p>
<p class="cnNmNjJhYTViMGMwODQ5Y2Y4Njg5YWJlMDc1YTc1ZTMy">“I'm kidding. Let's go.” I brush past her, looking back to see if she’s following.</p>
<p class="cnM1ZGJiM2UyN2Y1ZDQwYmFiMzFhYzI0MTNlMjFhYzI2">“Please line up in alphabetical order, a’s here, b’s here, c’s here...” the head lady at the front of the room tries to organize the room of chaotic teenagers. Me and Aza walk over to the lines, she steps into the girl's line, and I into the boy's line.</p>
<p class="cnM1Mzk3N2Y3YTI5ZjQyMjZhNDljNzU4YWY4YjI5OGU1">“Thank you everyone for being here.” the lady begins.</p>
<p class="cnNkMTAyNGQ5ZjJlMTQ4NmQ4ZDY5M2Q4Mjc2ZTUwZWEy">“Like we had a choice.” Aza mutters.</p>
<p class="cnNmNDA3OTBlMTk1ZTQyNjNhNzQ3ZTA0MzMxYjVmMmVl">“Shhh.” I shush her, not wanting either of us to get in trouble.</p>
<p class="cnNmZWFhOGIwZjY1NjQyMjk5ZmU5MzQxNmNkMzg1YzJk">“I'm going to call you two at a time, one female, and one male. First off, Caline Adams and Lynden Allen. Please follow the attendants towards the correct door.” the two step away from the lines, following the indicated attendants. “Renny Berg and Caelen Bramley.” I tune out the lady, imagining all the things that might happen to me if they find out about my FSS. Fear knots in my stomach, making me feel sick. “Gunner Fielding and Aza Felds.” The attendants walk towards us, flanking us on either side. We’re led to a long hallway with only three doors. One on each side, and one at the far end. Aza is led to the door on the right, and I, the door on the left. I expected a paper test with a pencil, but instead, on the floor, is what looks like one of those retro VR headsets but way more advanced.</p>
<p class="cnMwN2E0YmMyNGI5YTRlNGRiNzMyNWJiN2RjNTRkNjcx">“Please put the headset on and strap on the remotes. The test will begin shortly.” The attendant walks away. I do exactly as he says and pull the straps over my wrists. Instantly, little needle like pricks of pain per ice my skin and I yank off the straps. Little dots of blood well up on my skin. I ignore them and pull on the headset. A humming starts up in my ears, droning on as the “screen” lights up. A small part of my mind warns me to keep my FSS a secret, but a bigger part of screams ‘show the world! Share the secret!’ and the louder part wins. I’m sitting at a desk, surrounded by other desks. There’s a lined sheet of paper in front of me, a pencil in my hand. A teacher sits at the front of the room, looking over some other papers. I flip back through the pages, looking at my assignment. I read the prompt, and as I do, thoughts and facts fill my head. I put pencil to paper and words fill the page. Finishing the essay, satisfied with my argument, I put my pencil down. I stand up, gripping the pages in my hand, and the scene changes. A mic appears in my hand, held up to my mouth. A group of a couple hundred sits in front of me, waiting expectantly. I feel no nerves, even at the crowd of eyes staring at me. There’s a screen behind the crowd, words slowly moving towards the top. I take a deep breath. And speak. The words come; even thought I don’t remember rehearsing the speech. The words in my mind behind to differ from those in the screen. The scene changes as I’m dropped into the judge bench. Facts and opinions flood into my mind.</p>
<p class="cnMwZDg5OWY4OGVhZTRiYmU4M2FkOWViM2FkMzY1ZTg4">“Guilty!” I shout, slamming the gavel onto the block. As the gavel makes contact with the block, it changes to a hammer. I slowly hit the nail, connecting the plywood to the 2x4 stud. I walk to the hole in the wall, peering down the side of the building. And strong wind rushed through the skeleton of the building, knocking me off balance. I claw at the wall, trying to find a purchase, but I fall. I land on the raised platform in front of another room of people, though this room is smaller, and the audience is younger. I write notes on the digital whiteboard, talking about the NUS’s history. Pandemics that swept through the nation, civil wars that caused rifts between people groups. I’m just writing about the necessities people longed for during the virus COVID-19 when the headset is ripped forcefully off my head. I drop the remotes, and rough hands seize me at the elbows, dragging me to the door. I scramble to find footing and walk quickly into the hallway. Also being dragged into the hallway is Aza. There is a look of utmost fear upon her face. Down the hallway, the way we came from originally, a woman is pacing.</p>
<p class="cnNmZDBlODk3ZmU5ZjQyZjFiOGEzZDg0MGJmYjYwNzRj"><em>‘I must just tell them they are dead. I’m sorry but Aza and Gunner are dead. Yes, that sounds good. They died because of something in the simulation.’</em></p>
<p class="cnM5MWJkNjIxZmJmNjQ1YzU4ZGQ3YmIwY2ZjNDM1MWE5">What! Why did the MC from before just pop into my head!? And why is she saying that Aza and I are dead!? Is this what my parents meant by ‘special skills’? Am I reading minds? What other skills will I develop? I stare intently at the hat on the other guard's head, willing it to rise gently off his head. It doesn’t. We’re led down the hallway, towards the door at the end of the hallway. It opens without warning and outside is a hover plane, and wouldn’t you know it, it’s hovering above the ground, kicking up dust and leaves on the landing slab. Legs slide out from its underbelly, and it lands. Shutting off the engine, the bottom opens, exposing the inside. It’s all dark inside, like the creepy maw of some creature. The two guards lead is unto the plane, up the ramp and into a fenced-in enclosure like we’re wild animals. Maybe we are. He shuts the fence and walks away. The hatch closes as the engine starts up. Why are we here? What did we do?</p>
<p class="cnM2ODAwYWEwM2ZhNTQwNzI5MDAxNzk2NTI3NzJjNjEw">“You have it too.” Aza breaths. “That’s why we’re here. That’s what we did wrong. Being born with FSS is what they think we did wrong.” I just gape.</p>
<p class="cnM0NDcxNjE3NmNjNTQxMzFiYmRiMTg2YjAxYzQwZTBm">“Did you just read my mind?” I ask, shocked.</p>
<p class="cnNmMDQ0ZjE3YzhkZjQxNTBiZTRjMjY4NjZmZTdkNmY3">“No, I just happened to have a really lucky guess.” She sighs, “yes, you idiot! I read your mind. Didn’t you notice how every other person was brought back to the common room except us? Theres something ‘wrong’ with us so they’re gonna run tests on us to find out what it is! They want to learn how to stop people like us from being born!” She sniffs and looks at her hands, fidgeting. “My brother was like us. They took him when I was little and I haven’t seen him since.”&nbsp; She looks back up, and I see silent tears running down her face. I barely know her, but a crying girl is a crying girl. I awkwardly fold her into a hug, and her knees give out. We slide to the floor and she pulls away, wiping her face on her sleeve. Gross, but whatever.</p>
<p class="cnMxMzUzY2I2NzQ0OTQ5MTNiMzAxYjlhMDM0NjNlNTk3">“I’m sorry,” she says, “you just met me and I’m already crying my eyes out.” She sniffles again.</p>
<p class="cnM2OWRiMzNmNmMwODQ3YzBhODg3OTY5MmEwMTM0YmM3">“It’s ok. If you want, I can forget this ever happened,” I offer. She smiles.</p>
<p class="cnM4MDZlZDRkYjM2NTQ3YTA5NmJmNGJkMDExZWY2OWQ5">“You’re the first guy I’ve ever cried in front of, not counting when I was a child. Just don’t hold it against me.”</p>
<p class="cnM3ZTc1MzVjODczMTQ3NjVhM2UzZTIxODg0YmZhYzJh">“I won’t, and I’m flattered,” I stand up and hold out a hand. She takes it and pulls herself up. “Where do you think they’re taking us?” I ask after she’s released my hand.</p>
<p class="cnNkYWQzMmNkMWZjZTRjMzhiOTQ1OTNlNjhiMzQ3OTRi">“The compound.” A gravelly voice sounds from the corner of the plane chamber. They clear their throat. “The plane has been on the ground for almost 10 minutes already, please get out of your monkey cage and follow me.” What. Monkey cage? Is that what they think we are? Monkeys to be experimented on? I walk to the gate and push it open. Aza comes up behind me.</p>
<p class="cnNkNzYwMDgxYmM5OTQzMjY4NjczN2UyMjNmYzBmOTUz">“It wasn’t event locked?” I shake my head, and take a tentative step out, half expecting someone to spring a trap. No one does. Aza steps around me and marches up to the man standing in the shadows. “Why did you take us from our families? When can we go home? Are you gonna do tests on us?” She asks one question after another.</p>
<p class="cnMzNTUwMjEyMDgwODQwY2ZiOWFmYmExZTFjOTg3MjZh">“All of your questions will be answered when we arrive at the lab.” Is his response.</p>
<p class="cnMyY2ZhNWYzYTc1NDQxMjBiMzE5MTQ5NmM2NjIwZTY1">“But-” I cut her off.</p>
<p class="cnNhYWFlMTc5MTQzMzRiZmJhMDE1YTk4NzViZDI0NTc0">“Aza, if we want a chance at normal coloured skin, we got to stay on their good side,” I tell her. The man laughs and Aza sighs. The guy leads us out a side door and down a set of stairs. When we’re a safe distance away, the plane starts up again and takes off.</p>
<p class="cnM1ZjIzYTRmZWU5NzQ0MjE5MTZkMGZjYTQ3MTRmODhj">“Grayson, bring the children to cell 16. Lock the cell door this time, please.”&nbsp; A voice sounds from speakers mounted to the building's walls.</p>
<p class="cnNkMWE2NzYwN2VjMDQ5NDBhMDE4MWZlMTU4M2RiNTRk">“Like I don't know that already.” The guy mutters. He must be Grayson. He slides a key card into a slot in an elevator door. It slides open and we step in.</p>
<p class="cnMzNTAzMWFiY2U5MjQ4Yzk4NGFiNTM3ZmZkNjkwMzk4">&nbsp;</p>
<p class="cnMwZTNlOTZiYzZkZDQ2YmU5MjI5MTM4YTAxZWVjNWI4">&nbsp;</p>
<p class="cnNmODgxNTFjZmRjMjRjZGM4OTMwYmY1ZDA3OTg5OTA0">&nbsp;</p>
"""#

    private var p6: String { HierarchicalChunkerTests.p6 }

    private func endsSentence(_ s: String) -> Bool {
        var t = Substring(s)
        while let c = t.last, "\"'”’)]»".contains(c) { t = t.dropLast() }
        return t.last.map { ".!?…".contains($0) } ?? false
    }

    // MARK: Text splitter

    func testGiantParagraph6SplitsIntoThreeBalancedPiecesAtSentenceEnds() {
        XCTAssertEqual(p6.count, 2543)
        let pieces = ParagraphSplitter.pieces(p6)
        XCTAssertEqual(pieces.count, 3)
        XCTAssertEqual(pieces.map(\.count), [813, 872, 856])
        XCTAssertTrue(pieces.allSatisfy { (500...900).contains($0.count) }, "\(pieces.map(\.count))")
        XCTAssertTrue(pieces.allSatisfy(endsSentence))
        XCTAssertTrue(pieces[1].hasPrefix("There were hundreds of people"))
        XCTAssertTrue(pieces[2].hasPrefix("The first group, Scienta"))
        XCTAssertEqual(pieces.joined(separator: " "), p6, "text reassembles exactly")
    }

    func testCutOffsetsReassembleByteExact() {
        for para in [p6, HierarchicalChunkerTests.p7] {
            let offs = ParagraphSplitter.pieceStartUTF8Offsets(para)
            XCTAssertFalse(offs.isEmpty)
            let bytes = Array(para.utf8)
            var rebuilt: [String] = []
            var start = 0
            for o in offs + [bytes.count] {
                rebuilt.append(String(decoding: bytes[start..<o], as: UTF8.self))
                start = o
            }
            XCTAssertEqual(rebuilt.joined(), para)
            XCTAssertEqual(rebuilt.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }, ParagraphSplitter.pieces(para))
        }
    }

    func testChapterParagraphsOverThresholdOnlyAndBalanced() {
        let paras = ListenHTMLBlocks.leafTexts(fromHTML: Self.chapterHTML)
        var splitSizes: [[Int]] = []
        for p in paras {
            let pieces = ParagraphSplitter.pieces(p)
            if p.count <= ParagraphSplitter.threshold {
                XCTAssertEqual(pieces, [p], "never split ≤ 1,200 chars")
                continue
            }
            XCTAssertGreaterThan(pieces.count, 1)
            XCTAssertEqual(pieces.joined(separator: " "), p)
            XCTAssertTrue(pieces.dropLast().allSatisfy(endsSentence), "cut mid-sentence: \(pieces.map { $0.suffix(30) })")
            let sizes = pieces.map(\.count)
            XCTAssertLessThanOrEqual(Double(sizes.max()!) / Double(sizes.min()!), 1.3, "balanced: \(sizes)")
            splitSizes.append(sizes)
        }
        // p6 2,543 → 3; p7 1,397 → 2; the courtroom paragraph 1,560 → 2. p15 (1,121) stays.
        XCTAssertEqual(splitSizes, [[813, 872, 856], [722, 674], [803, 756]])
    }

    func testNoSplitWhenOnlyUnbalancedCutsExist() {
        let long = String(repeating: "word ", count: 235) + "end."          // one 1,179-char sentence
        let para = long + " " + "Short tail sentence here, only a little text."
        XCTAssertGreaterThan(para.count, 1200)
        XCTAssertEqual(ParagraphSplitter.pieces(para), [para], "a tiny tail is not worth a split")
        let oneSentence = String(repeating: "and so on ", count: 150) + "done."
        XCTAssertEqual(ParagraphSplitter.pieces(oneSentence), [oneSentence], "a single giant sentence stays whole")
    }

    func testAbbreviationsAndInitialsAreNotCutPoints() {
        let s1 = String(repeating: "The committee met again today and argued for a long while. ", count: 10)
        let mid = "President I. Ericcson-Sprucefeld met Dr. Smith in the U.S.A. with etc-. The talks went well. "
        let para = (s1 + mid + s1).trimmingCharacters(in: .whitespaces)
        let pieces = ParagraphSplitter.pieces(para)
        XCTAssertGreaterThan(pieces.count, 1)
        for p in pieces {
            XCTAssertFalse(p.hasSuffix("I.") || p.hasSuffix("Dr.") || p.hasPrefix("Ericcson") || p.hasPrefix("Smith"))
        }
    }

    // MARK: HTML (display) == listen list

    func testHTMLSplitMatchesTextSplitOnRealChapter() {
        let before = ListenHTMLBlocks.leafTexts(fromHTML: Self.chapterHTML)
        let split = ListenHTMLBlocks.splitLongBlocks(Self.chapterHTML)
        let after = ListenHTMLBlocks.leafTexts(fromHTML: split)
        XCTAssertEqual(after, before.flatMap(ParagraphSplitter.pieces))
        XCTAssertEqual(after.count, before.count + 4)
        // Only tags were inserted: removing them gives back the same text.
        func strip(_ h: String) -> String {
            h.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        }
        XCTAssertEqual(strip(split), strip(Self.chapterHTML))
        XCTAssertEqual(split.components(separatedBy: "<p").count, Self.chapterHTML.components(separatedBy: "<p").count + 4)
        XCTAssertEqual(ListenHTMLBlocks.splitLongBlocks(split), split, "idempotent")
    }

    func testHTMLSplitClosesAndReopensInlineTagsAndDropsIDs() {
        let s = String(repeating: "Plain words fill this sentence up nicely. ", count: 16)
        let html = #"<p id="big" class="c">"# + s + #"<em class="x">An emphasised sentence ends here. And "#
            + #"it continues</em> <a href="u">"# + s + "</a> &ldquo;Quoted end.&rdquo; " + s + "</p><p id=\"small\">Tiny.</p>"
        let out = ListenHTMLBlocks.splitLongBlocks(html)
        let before = ListenHTMLBlocks.leafTexts(fromHTML: html)
        XCTAssertEqual(ListenHTMLBlocks.leafTexts(fromHTML: out), before.flatMap(ParagraphSplitter.pieces))
        XCTAssertGreaterThan(ListenHTMLBlocks.leafTexts(fromHTML: out).count, 2)
        XCTAssertEqual(out.components(separatedBy: "id=\"big\"").count, 2, "id kept once")
        XCTAssertEqual(out.components(separatedBy: "<em").count, out.components(separatedBy: "</em>").count)
        XCTAssertEqual(out.components(separatedBy: "<a ").count, out.components(separatedBy: "</a>").count)
        XCTAssertTrue(out.contains(#"class="c""#))
    }

    func testReaderViewIndicesMatchListenParagraphs() {
        let extracted = ExtractedArticle(title: "Prologue / Chapter One: Gunner", siteName: "Royal Road",
                                         cleanedHTML: Self.chapterHTML, plainText: "", excerpt: "")
        let article = ReaderArticle(id: UUID(), url: URL(string: "https://www.royalroad.com/fiction/178276/the-forgotten/chapter/3628466/prologue-chapter-one--gunner")!,
                                    extracted: extracted)
        // What the web view indexes (displayHTML leaves) is exactly the listen / queue list.
        XCTAssertEqual(ListenHTMLBlocks.leafTexts(fromHTML: article.displayHTML), article.document.paragraphs)
        XCTAssertTrue(article.document.paragraphs.allSatisfy { $0.count <= ParagraphSplitter.threshold })
    }

    func testPlainTextPathSplitsTheSameWay() {
        let doc = ParagraphDocument(plainText: "Title\n\n" + p6 + "\n\nAfter.")
        XCTAssertEqual(doc.paragraphs, ["Title"] + ParagraphSplitter.pieces(p6) + ["After."])
        XCTAssertEqual(ParagraphDocument(plainText: "Title\n\n" + p6, splitLong: false).count, 2)
    }

    // MARK: Position mapping

    func testPositionMapsToSameSentence() {
        let old = ParagraphDocument(parts: ListenHTMLBlocks.leafTexts(fromHTML: Self.chapterHTML))
        let new = ParagraphDocument(html: ListenHTMLBlocks.splitLongBlocks(Self.chapterHTML))
        let i6 = old.paragraphs.firstIndex { $0.hasPrefix("Okay, I’m gonna give you") }!
        let text = old.paragraphs[i6] as NSString
        let inPiece2 = old.utf16Ranges[i6].location + text.range(of: "There were hundreds").location
        let midWord = old.utf16Ranges[i6].location + text.range(of: "Scienta").location + 3
        let p = ParagraphPositionMap.map(paragraph: i6, utf16Offset: inPiece2, from: old, to: new)
        XCTAssertEqual(p.paragraph, i6 + 1)
        XCTAssertTrue(new.paragraphs[p.paragraph].hasPrefix("There were hundreds"))
        XCTAssertEqual(p.utf16Offset, new.utf16Ranges[i6 + 1].location)
        let q = ParagraphPositionMap.map(paragraph: i6, utf16Offset: midWord, from: old, to: new)
        XCTAssertEqual(q.paragraph, i6 + 2)
        XCTAssertEqual((new.joinedText as NSString).substring(with: NSRange(location: q.utf16Offset, length: 4)), "enta")
        // Stale offset (not inside the paragraph) → paragraph start → first piece.
        XCTAssertEqual(ParagraphPositionMap.map(paragraph: i6, utf16Offset: 0, from: old, to: new).paragraph, i6)
        // Later paragraphs shift by the number of extra pieces before them.
        let iLast = old.count - 1
        XCTAssertEqual(ParagraphPositionMap.mapParagraphStart(iLast, from: old, to: new), new.count - 1)
        let i8 = i6 + 2 // unsplit paragraph after p6 (+2) and p7 (+1)
        XCTAssertEqual(new.paragraphs[ParagraphPositionMap.mapParagraphStart(i8, from: old, to: new)], old.paragraphs[i8])
    }
}

/// Migration of saved articles + their audio cache to layout v3.
@MainActor
final class ParagraphLayoutMigrationTests: XCTestCase {
    private var cleanups: [() -> Void] = []
    override func tearDown() {
        cleanups.forEach { $0() }
        cleanups = []
        ListenResumePointStore.shared.clear()
        super.tearDown()
    }

    private func makeCoordinator() -> LocalTTSCoordinator {
        let suite = "LayoutMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let tmp = FileManager.default.temporaryDirectory
        let root = tmp.appendingPathComponent("LayoutMig-\(UUID().uuidString)")
        let guardDir = tmp.appendingPathComponent("LayoutMigGuard-\(UUID().uuidString)")
        cleanups.append {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: guardDir)
        }
        let registry = EngineRegistry(providers: [AppleSpeechProvider(), KokoroStubProvider()], gate: { _ in true })
        return LocalTTSCoordinator(engines: registry, defaults: defaults, audioCache: ArticleAudioCache(root: root),
                                   crashGuard: EngineCrashGuard(directory: guardDir))
    }

    /// A stitched paragraph CAF like the queue writes: chunk k = `lengths[k]` samples of value k+1.
    private func writeStitched(_ cache: ArticleAudioCache, article: UUID, index: Int, text: String,
                               lengths: [Int]) throws {
        var samples: [Float] = []
        for (k, n) in lengths.enumerated() { samples += [Float](repeating: Float(k + 1) / 100, count: n) }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stitch-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try LocalPCMWriter.write(samples, sampleRate: 24_000, to: tmp)
        try cache.storeParagraph(articleID: article, paragraphIndex: index, sourceURL: tmp,
                                 duration: Double(samples.count) / 24_000, engineID: SpeechEngineID.kokoro.rawValue,
                                 voiceID: "kstub:af_heart", rate: 1, text: text,
                                 chunkDurations: lengths.count > 1 ? lengths.map { Double($0) / 24_000 } : nil)
    }

    private func int16Samples(_ url: URL) throws -> [Int16] {
        let f = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let b = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length))!
        try f.read(into: b)
        return Array(UnsafeBufferPointer(start: b.int16ChannelData![0], count: Int(b.frameLength)))
    }

    func testSavedArticleMigrationKeepsPositionAndOnlyInvalidatesSplitAudio() throws {
        let coordinator = makeCoordinator()
        let cache = coordinator.audioCache
        let container = try ModelContainer(for: SavedArticle.self, RecentVisit.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let html = ParagraphSplitTests.chapterHTML
        let title = "Prologue / Chapter One: Gunner"
        let oldList = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title, splitLong: false)
        let i6 = oldList.paragraphs.firstIndex { $0.hasPrefix("Okay, I’m gonna give you") }!
        let old6 = oldList.paragraphs[i6] as NSString
        let offset = oldList.utf16Ranges[i6].location + old6.range(of: "The first group, Scienta").location

        let row = SavedArticle(urlString: "https://www.royalroad.com/fiction/178276/the-forgotten/chapter/3628466/prologue-chapter-one--gunner",
                               title: title, siteDomain: "www.royalroad.com", cleanedHTML: html, plainText: "",
                               wordCount: 3000, estimatedMinutes: 15, excerpt: "",
                               playbackParagraphIndex: i6, playbackUTF16Offset: offset)
        row.listenBlocksData = try JSONEncoder().encode(oldList.paragraphs)
        row.listenBlocksVersion = 2
        context.insert(row)
        try context.save()

        // Audio as rendered before the split: p6 (15 chunks), p6+1 and the last paragraph.
        let plan6 = TextChunker.chunks(for: oldList.paragraphs[i6], limits: .kokoroCPU)
        let lengths = plan6.indices.map { 2400 + 240 * $0 }
        try writeStitched(cache, article: row.id, index: i6, text: oldList.paragraphs[i6], lengths: lengths)
        let iAfter = i6 + 2 // p8 (after p7, which also splits)
        try writeStitched(cache, article: row.id, index: iAfter, text: oldList.paragraphs[iAfter], lengths: [4800])
        let iLast = oldList.count - 1
        try writeStitched(cache, article: row.id, index: iLast, text: oldList.paragraphs[iLast], lengths: [4800])
        ListenResumePointStore.shared.save(article: row.id, paragraph: iAfter)
        // A crash-resume target read at coordinator init (before migration) — old numbering.
        coordinator.pendingResume = ListenResumeTarget(articleKey: row.id.uuidString, paragraph: iAfter, at: Date())

        let report = ArticleLibrary.migrateParagraphLayout(in: context, localTTS: coordinator)
        XCTAssertEqual(report.articles, 1)
        XCTAssertEqual(report.newParagraphs, report.oldParagraphs + 4)
        XCTAssertEqual(report.splitParagraphs, 3)

        let new = row.listenDocument()
        XCTAssertEqual(row.listenBlocksVersion, ListenHTMLBlocks.version)
        XCTAssertEqual(new.paragraphs, ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: title).paragraphs)
        // Position: same sentence ("The first group…" starts piece 3 of old p6).
        XCTAssertEqual(row.playbackParagraphIndex, i6 + 2)
        XCTAssertTrue(new.paragraphs[row.playbackParagraphIndex].hasPrefix("The first group, Scienta"))
        XCTAssertEqual(row.playbackUTF16Offset, new.utf16Ranges[i6 + 2].location)
        // Crash-resume point follows its paragraph.
        XCTAssertEqual(ListenResumePointStore.shared.load()?.paragraph, iAfter + 3)
        XCTAssertEqual(coordinator.pendingResume?.paragraph, iAfter + 3, "in-memory crash target remapped too")

        // Unsplit paragraphs keep their audio at the shifted index.
        let entryAfter = cache.entry(articleID: row.id, paragraphIndex: iAfter + 3)
        XCTAssertEqual(entryAfter?.textHash, ArticleIdentity.paragraphHash(oldList.paragraphs[iAfter]))
        XCTAssertEqual(cache.entry(articleID: row.id, paragraphIndex: new.count - 1)?.textHash,
                       ArticleIdentity.paragraphHash(oldList.paragraphs[iLast]))
        // Split paragraph: a piece keeps audio only if its chunk plan lines up with the old chunks.
        var from = 0
        for k in 0..<3 {
            let piece = new.paragraphs[i6 + k]
            let plan = TextChunker.chunks(for: piece, limits: .kokoroCPU)
            var q: Int?
            var s = from
            while s + plan.count <= plan6.count { if Array(plan6[s..<(s + plan.count)]) == plan { q = s; break }; s += 1 }
            let entry = cache.entry(articleID: row.id, paragraphIndex: i6 + k)
            guard let q else { XCTAssertNil(entry, "misaligned piece \(k) must re-render"); continue }
            from = q + plan.count
            let e = try XCTUnwrap(entry, "aligned piece \(k) keeps audio")
            XCTAssertEqual(e.textHash, ArticleIdentity.paragraphHash(piece))
            let samples = try int16Samples(cache.directory(for: row.id).appendingPathComponent(e.file))
            XCTAssertEqual(samples.count, lengths[q..<(q + plan.count)].reduce(0, +), "sample-exact slice")
            XCTAssertEqual(samples.first, Int16(Float(q + 1) / 100 * 32767))
            XCTAssertEqual(samples.last, Int16(Float(q + plan.count) / 100 * 32767))
        }
        XCTAssertNotNil(cache.entry(articleID: row.id, paragraphIndex: i6), "piece 1 of p6 lines up with the old first chunks")
        // Idempotent.
        XCTAssertEqual(ArticleLibrary.migrateParagraphLayout(in: context, localTTS: coordinator).articles, 0)
    }

    func testBrowseOpenAlignsEphemeralCacheTheSameWay() throws {
        let coordinator = makeCoordinator()
        let cache = coordinator.audioCache
        let html = ParagraphSplitTests.chapterHTML
        let url = URL(string: "https://www.royalroad.com/fiction/178276/the-forgotten/chapter/3628466/prologue-chapter-one--gunner")!
        let extracted = ExtractedArticle(title: "Gunner", siteName: nil, cleanedHTML: html, plainText: "", excerpt: "")
        let article = ReaderArticle(id: ArticleIdentity.articleKey(url: url), url: url, extracted: extracted)
        let oldList = ParagraphDocument.forListening(plainText: "", cleanedHTML: html, matchingTitle: "Gunner", splitLong: false)
        let iLast = oldList.count - 1
        try writeStitched(cache, article: article.id, index: iLast, text: oldList.paragraphs[iLast], lengths: [4800])
        coordinator.prepareListenIdentity(key: article.id, paragraphs: article.document.paragraphs)
        XCTAssertEqual(cache.entry(articleID: article.id, paragraphIndex: article.document.count - 1)?.textHash,
                       ArticleIdentity.paragraphHash(oldList.paragraphs[iLast]))
        XCTAssertNil(cache.entry(articleID: article.id, paragraphIndex: iLast))
    }
}
