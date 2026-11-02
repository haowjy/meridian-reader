#if DEBUG
import Foundation

/// `-seedMarketingLibrary`'s content (Debug builds only): six original essays, a public-domain book
/// (Jane Austen, *Pride and Prejudice*, chapters 1-3, Project Gutenberg) and the folders they sit in,
/// written for the App Store screenshots. The text is as written; sources and licences are in the
/// screenshot capture notes. Never copy real people's content in here.
enum MarketingContent {
    struct Essay {
        var title: String
        var site: String
        var address: String
        /// Days before the hero essay was added, so the library looks lived-in.
        var daysBeforeHero: Int
        var folder: String?
        var paragraphs: [String]
    }

    struct Book {
        var title: String
        var author: String
        var chapters: [(title: String, paragraphs: [String])]
    }

    /// The essay Listen and the Browser's reader mode open on: the newest added.
    static let hero = "A City in the Rain"

    static let folders = [#"City Walks"#, #"Natural History"#, #"At the Table"#, #"Weekend Reading"#]

    /// Oldest first; the hero last.
    static let essays: [Essay] = [
        Essay(title: #"The Garden After Dusk"#, site: #"Night Window"#, address: #"https://night-window.example.com/nature/garden-after-dusk"#, daysBeforeHero: 31,
              folder: nil, paragraphs: [
            #"A garden after dusk is not an empty garden. The familiar shapes are still there, but color gives way to outline, and the eye has to work more slowly. A fence becomes a dark band; the path is easier to read where pale stones catch the last light. Standing still for a moment reveals how much of the daytime scene depended on color and movement."#,
            #"The air often feels cooler near the ground, where leaves and soil release the day’s stored warmth. A breeze moves through the taller stems before it reaches the small plants along the path. The garden’s sounds become distinct as other activity fades: a leaf brushing a fence, water shifting in a saucer, a distant door closing. Each sound seems to have more space around it."#,
            #"Some flowers open or release their strongest scent in the evening, while others fold inward as the light changes. A garden planted with different forms and flowering times can offer something to notice across the day. It need not be large. A pot by a doorway, a strip beside a walk, or a single climbing plant can make a threshold feel like a place to pause."#,
            #"Insects follow many different rhythms, and dusk can be a busy part of the day for some of them. A pale blossom may be easier to find in low light than a dark one, while fragrance can travel beyond the edge of a bed. These small relationships invite observation without requiring a name for every visitor. The first question can simply be: what changed after sunset?"#,
            #"A porch light affects the scene around it. Moths and other insects may gather near a bright lamp, while the corners beyond it remain difficult to see. A shielded, modest light keeps the path legible and leaves more of the garden dark enough for night to feel like night. The choice is practical, but it also changes which parts of the garden are visible to us."#,
            #"Before going in, take one slow look from the same place you use in daylight. Notice a shape that has disappeared and a sound that has arrived. The garden has not become mysterious; it has become less available to a quick glance. Returning to it after dark is a simple way to practice attention when the usual visual cues are gone."#,
        ]),
        Essay(title: #"Clay, Hands, and the Turning Wheel"#, site: #"Kiln & Coast"#, address: #"https://kiln-coast.example.com/craft/clay-hands-wheel"#, daysBeforeHero: 24,
              folder: #"Weekend Reading"#, paragraphs: [
            #"The potter’s wheel is often treated as the emblem of pottery, though it is only one way to shape clay. Its turning surface helps the hands repeat a circular movement, and that repetition can raise a wall from a centered lump. The result depends less on speed than on balance: the clay must remain centered, and the hands must work together without forcing it out of shape."#,
            #"Long before a vessel reaches the wheel, clay has to be prepared. Kneading presses out air pockets and makes the material more even. A potter may wedge it on a table with a steady rocking motion, folding the clay over itself again and again. The work is practical and quiet. It gives the hands a chance to notice whether the clay feels stiff, sticky, or ready to move."#,
            #"When the wheel turns, one hand often supports the clay from outside while the other presses from within. The space between them becomes the wall of a pot. A small change in pressure can widen a bowl or lengthen a cup. This is why watching a skilled potter can feel surprising: the movement looks modest, but the wet clay responds immediately to it."#,
            #"A shaped pot still needs to dry before it can be fired. If moisture leaves too quickly or unevenly, the clay can warp or crack. The drying stage asks for patience that is less visible than the wheel work. A piece may sit under a loose cover while the surface firms, then wait until it is dry enough to handle without losing its form."#,
            #"Firing changes the clay in ways that cannot be undone by adding water. Heat drives out remaining moisture and makes the body hard. A glaze, when used, melts into a thin glassy coating under the right conditions. The final color may be difficult to predict from raw materials alone, so potters keep records of clay bodies, glazes, and kiln conditions for the next firing."#,
            #"A handmade cup carries these stages in its shape. The rim may hold a faint variation where a thumb guided the clay; the foot may show where it was separated from the wheel. Such marks need not be mistakes. They are clues to a sequence of decisions, from preparing the clay to opening the kiln, and to the fact that a useful object can also show how it was made."#,
        ]),
        Essay(title: #"The Sound of a Tuning Fork"#, site: #"Open Interval"#, address: #"https://open-interval.example.com/science/tuning-fork"#, daysBeforeHero: 17,
              folder: #"Natural History"#, paragraphs: [
            #"A tuning fork looks almost too plain to be an instrument. Two metal prongs rise from a handle, with no keys, strings, or hollow body to suggest a melody. Tap it gently against a firm surface and the prongs begin to vibrate. Held near the ear, the fork offers a steady tone: simple enough to recognize, and rich enough to make the surrounding room feel newly audible."#,
            #"The sound comes from the prongs moving rapidly back and forth. Their motion pushes the air around them into repeating pressure changes, which travel outward as sound waves. The handle carries some vibration too. Touch it lightly to a tabletop and the table can pass the motion into a larger area, making the tone louder without changing the fork’s basic pitch."#,
            #"A fork’s pitch depends on its shape, material, and size. A short, stiff prong tends to vibrate faster than a longer, more flexible one. Faster vibration means a higher frequency, which people generally hear as a higher note. The paired prongs move together in a regular pattern, and the ear hears that pattern as a stable pitch. That is why forks are labeled with their note."#,
            #"This steadiness makes a tuning fork useful as a reference. Musicians can compare another sound with it, while instrument makers can use it to check whether a string or pipe is close to a target note. A fork does not tell you everything about a sound. It offers one clear point of comparison, like a straight edge placed beside a complicated curve."#,
            #"The tone fades because energy leaves the vibrating fork. Air carries some away; a surface touched by the handle can carry more. The motion becomes smaller until the sound slips below what we can hear. Nothing in the fork has been switched off. It has simply given its stored motion to the world around it, in amounts too small to notice one by one."#,
            #"Try listening in a quiet room, then repeat the experiment with the handle touching a wooden table. The pitch remains recognizable, but the room seems to join in. That difference connects a small object to a larger idea: sounds are not only made by their sources. They are shaped by the materials, spaces, and listeners that meet along the way."#,
        ]),
        Essay(title: #"A Small Map of Bread"#, site: #"The Table Letter"#, address: #"https://table-letter.example.com/kitchen/small-map-of-bread"#, daysBeforeHero: 12,
              folder: #"At the Table"#, paragraphs: [
            #"A loaf begins as a set of choices made with the hands. How wet should the dough feel? How long can it rest before the next fold? The answers change with flour, room temperature, and the baker’s habits. A recipe gives a path through those questions, but touch supplies the small corrections that turn instructions into a loaf suited to this kitchen, on this day."#,
            #"Flour and water make a simple mixture, yet time gives it structure. As the dough rests, it becomes easier to stretch and fold without tearing. Yeast produces gas that expands the dough, while gluten forms a network that helps hold it. These processes do not happen on a tidy clock. The baker watches for signs: a smoother skin, a little lift, a soft spring beneath a fingertip."#,
            #"Salt is easy to treat as a final seasoning, but in bread it belongs to the dough from the start. It sharpens flavor and affects how the dough behaves as it rises. The amount is modest, which makes a scale useful: a small difference can be hard to judge by eye when the other ingredients are measured in larger piles. A pinch is easier to repeat when weighed."#,
            #"Shaping gathers the dough’s surface into tension. A few deliberate turns create a skin that helps the loaf keep its form in the oven. Too much handling can press out the air the dough has gathered; too little can leave it slack. The movement is brief, but it carries the memory of every fold that came before. A light touch leaves the dough room to rise."#,
            #"The first cut across a loaf is a tiny record of its baking. A crisp crust gives way to a soft interior, and the pattern of holes changes from slice to slice. Bakers sometimes call that interior the crumb. Its texture reflects the dough and fermentation, but it also makes the bread useful in different ways: close and even for toast, open and chewy for soup."#,
            #"Keeping a bread notebook need not become a project. Write down the flour, the room’s rough warmth, and when the dough looked ready. Add one sentence about what you would change next time. The note turns an ordinary breakfast into an experiment with a pleasant ending, and the loaf becomes a small map of the choices that made it. Those notes make the next loaf easier to read."#,
        ]),
        Essay(title: #"The Patient Work of Moss"#, site: #"Fieldglass"#, address: #"https://fieldglass.example.com/nature/patient-work-of-moss"#, daysBeforeHero: 7,
              folder: #"Natural History"#, paragraphs: [
            #"Moss is easy to overlook because it makes no announcement. It spreads in cushions along a shaded wall, gathers at the foot of a tree, or settles into the seam between stones. From standing height it can look like a single green surface. Close down, its texture breaks into tiny stems and leaves, each part holding a different glint of moisture or shadow."#,
            #"A mossy patch changes with the air around it. After rain, it looks fuller and brighter; during a dry spell, many kinds curl inward and lose some of their vivid color. This visible shift can make the same stone seem to host two different landscapes. The plant is still there, waiting through conditions that would leave a broad, delicate leaf looking tired."#,
            #"The surface beneath moss matters. Bark, old brick, and stone each offer a different arrangement of cracks and ledges where water can linger. A patch often follows those small features rather than forming a neat circle. Watching its edge is a way to notice the wall itself: where mortar has worn back, where a branch casts shade, or where a drip keeps returning."#,
            #"Moss has no roots that reach deep into soil in the way a garden plant does. Its fine anchoring structures attach it to a surface, while water and dissolved nutrients arrive across its exposed body. That arrangement helps explain why it appears in places too shallow or awkward for many other plants. It also explains why a boot or a brushing sleeve can damage a patch so easily."#,
            #"On a walk, the best view may be from a little distance and then from close enough to see the detail. A phone camera can help, but so can leaning nearer and letting your eyes adjust to the small scale. The green field resolves into layers, and a dry brown stalk or a fallen seed becomes part of the scene rather than a flaw in it."#,
            #"Moss rewards a slower kind of looking. It does not need a dramatic setting: a shaded step or the north side of a planter can be enough. Its quiet presence makes damp corners feel inhabited, even when no animal is visible. The next time a path is slick after rain, the green along its edge may be a record of shade, water, and time."#,
        ]),
        Essay(title: #"A City in the Rain"#, site: #"Common Ground Journal"#, address: #"https://common-ground.example.com/field-notes/city-in-rain"#, daysBeforeHero: 0,
              folder: #"City Walks"#, paragraphs: [
            #"Rain changes the scale of a city. A familiar avenue narrows to the bright strip beneath an awning; a crossing becomes a small negotiation between shoes, umbrellas, and turning traffic. The buildings have not moved, but their edges soften in the wet air. Even a route taken every day asks for a little more attention, as if the weather has quietly edited out the background."#,
            #"At the corner, people gather where the shop canopy reaches furthest over the pavement. Nobody has arranged them, yet the group forms a temporary room, open on three sides and roofed in green canvas. A cyclist waits at the curb with one hand on the brake. A delivery worker checks a phone. For a minute, strangers share the same dry patch and the same view of the street."#,
            #"Water gives windows a second life. In the glass, the lamps behind you float over the street ahead, and a bus passes through both scenes at once. The reflection is not sharp enough to mistake for the real thing. It is more like a note in the margin: the city is made of what stands in front of us and what we carry past it."#,
            #"The sound changes too. Tires make a steady hush on wet pavement, while a gutter gathers drops into a brief, uneven rhythm. A door opens and lets out the warmer sounds of a café: cups, talk, the bell above the frame. Then it closes, and the street returns to its softer register. Rain does not make the city quiet; it rearranges which sounds reach us first."#,
            #"At the next block, a tree holds beads of water along its smallest branches. The leaves turn each one into a pinprick of light when a gap opens in the clouds. Beneath them, someone has set a paper bag on a low wall to free both hands for an umbrella. Small adjustments like these are the real choreography of a wet afternoon."#,
            #"By the time the rain thins, the sidewalks are already changing back. People shorten their steps, umbrellas tilt closed, and bright reflections retreat into shallow puddles. The route home is still the route home, but it has offered a different set of landmarks: the shared awning, the doubled windows, the tree holding the last drops. A city can be reread without going anywhere new."#,
        ]),
    ]

    static let book = Book(title: #"Pride and Prejudice"#, author: #"Jane Austen"#, chapters: [
        (title: #"Chapter I."#, paragraphs: [
            #"It is a truth universally acknowledged, that a single man in possession of a good fortune must be in want of a wife."#,
            #"However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered as the rightful property of some one or other of their daughters."#,
            #"“My dear Mr. Bennet,” said his lady to him one day, “have you heard that Netherfield Park is let at last?”"#,
            #"Mr. Bennet replied that he had not."#,
            #"“But it is,” returned she; “for Mrs. Long has just been here, and she told me all about it.”"#,
            #"Mr. Bennet made no answer."#,
            #"“Do not you want to know who has taken it?” cried his wife, impatiently."#,
            #"“_You_ want to tell me, and I have no objection to hearing it.”"#,
            #"This was invitation enough."#,
            #"“Why, my dear, you must know, Mrs. Long says that Netherfield is taken by a young man of large fortune from the north of England; that he came down on Monday in a chaise and four to see the place, and was so much delighted with it that he agreed with Mr. Morris immediately; that he is to take possession before Michaelmas, and some of his servants are to be in the house by the end of next week.”"#,
            #"“What is his name?”"#,
            #"“Bingley.”"#,
            #"“Is he married or single?”"#,
            #"“Oh, single, my dear, to be sure! A single man of large fortune; four or five thousand a year. What a fine thing for our girls!”"#,
            #"“How so? how can it affect them?”"#,
            #"“My dear Mr. Bennet,” replied his wife, “how can you be so tiresome? You must know that I am thinking of his marrying one of them.”"#,
            #"“Is that his design in settling here?”"#,
            #"“Design? Nonsense, how can you talk so! But it is very likely that he _may_ fall in love with one of them, and therefore you must visit him as soon as he comes.”"#,
            #"“I see no occasion for that. You and the girls may go--or you may send them by themselves, which perhaps will be still better; for as you are as handsome as any of them, Mr. Bingley might like you the best of the party.”"#,
            #"“My dear, you flatter me. I certainly _have_ had my share of beauty, but I do not pretend to be anything extraordinary now. When a woman has five grown-up daughters, she ought to give over thinking of her own beauty.”"#,
            #"“In such cases, a woman has not often much beauty to think of.”"#,
            #"“But, my dear, you must indeed go and see Mr. Bingley when he comes into the neighbourhood.”"#,
            #"“It is more than I engage for, I assure you.”"#,
            #"“But consider your daughters. Only think what an establishment it would be for one of them. Sir William and Lady Lucas are determined to go, merely on that account; for in general, you know, they visit no new comers. Indeed you must go, for it will be impossible for _us_ to visit him, if you do not.”"#,
            #"“You are over scrupulous, surely. I dare say Mr. Bingley will be very glad to see you; and I will send a few lines by you to assure him of my hearty consent to his marrying whichever he chooses of the girls--though I must throw in a good word for my little Lizzy.”"#,
            #"“I desire you will do no such thing. Lizzy is not a bit better than the others: and I am sure she is not half so handsome as Jane, nor half so good-humoured as Lydia. But you are always giving _her_ the preference.”"#,
            #"“They have none of them much to recommend them,” replied he: “they are all silly and ignorant like other girls; but Lizzy has something more of quickness than her sisters.”"#,
            #"“Mr. Bennet, how can you abuse your own children in such a way? You take delight in vexing me. You have no compassion on my poor nerves.”"#,
            #"“You mistake me, my dear. I have a high respect for your nerves. They are my old friends. I have heard you mention them with consideration these twenty years at least.”"#,
            #"“Ah, you do not know what I suffer.”"#,
            #"“But I hope you will get over it, and live to see many young men of four thousand a year come into the neighbourhood.”"#,
            #"“It will be no use to us, if twenty such should come, since you will not visit them.”"#,
            #"“Depend upon it, my dear, that when there are twenty, I will visit them all.”"#,
            #"Mr. Bennet was so odd a mixture of quick parts, sarcastic humour, reserve, and caprice, that the experience of three-and-twenty years had been insufficient to make his wife understand his character. _Her_ mind was less difficult to develope. She was a woman of mean understanding, little information, and uncertain temper. When she was discontented, she fancied herself nervous. The business of her life was to get her daughters married: its solace was visiting and news."#,
        ]),
        (title: #"CHAPTER II."#, paragraphs: [
            #"[Illustration"#,
            #"Mr. Bennet was among the earliest of those who waited on Mr. Bingley. He had always intended to visit him, though to the last always assuring his wife that he should not go; and till the evening after the visit was paid she had no knowledge of it. It was then disclosed in the following manner. Observing his second daughter employed in trimming a hat, he suddenly addressed her with,--"#,
            #"“I hope Mr. Bingley will like it, Lizzy.”"#,
            #"“We are not in a way to know _what_ Mr. Bingley likes,” said her mother, resentfully, “since we are not to visit.”"#,
            #"“But you forget, mamma,” said Elizabeth, “that we shall meet him at the assemblies, and that Mrs. Long has promised to introduce him.”"#,
            #"“I do not believe Mrs. Long will do any such thing. She has two nieces of her own. She is a selfish, hypocritical woman, and I have no opinion of her.”"#,
            #"“No more have I,” said Mr. Bennet; “and I am glad to find that you do not depend on her serving you.”"#,
            #"Mrs. Bennet deigned not to make any reply; but, unable to contain herself, began scolding one of her daughters."#,
            #"“Don’t keep coughing so, Kitty, for heaven’s sake! Have a little compassion on my nerves. You tear them to pieces.”"#,
            #"“Kitty has no discretion in her coughs,” said her father; “she times them ill.”"#,
            #"“I do not cough for my own amusement,” replied Kitty, fretfully. “When is your next ball to be, Lizzy?”"#,
            #"“To-morrow fortnight.”"#,
            #"“Ay, so it is,” cried her mother, “and Mrs. Long does not come back till the day before; so, it will be impossible for her to introduce him, for she will not know him herself.”"#,
            #"“Then, my dear, you may have the advantage of your friend, and introduce Mr. Bingley to _her_.”"#,
            #"“Impossible, Mr. Bennet, impossible, when I am not acquainted with him myself; how can you be so teasing?”"#,
            #"“I honour your circumspection. A fortnight’s acquaintance is certainly very little. One cannot know what a man really is by the end of a fortnight. But if _we_ do not venture, somebody else will; and after all, Mrs. Long and her nieces must stand their chance; and, therefore, as she will think it an act of kindness, if you decline the office, I will take it on myself.”"#,
            #"The girls stared at their father. Mrs. Bennet said only, “Nonsense, nonsense!”"#,
            #"“What can be the meaning of that emphatic exclamation?” cried he. “Do you consider the forms of introduction, and the stress that is laid on them, as nonsense? I cannot quite agree with you _there_. What say you, Mary? For you are a young lady of deep reflection, I know, and read great books, and make extracts.”"#,
            #"Mary wished to say something very sensible, but knew not how."#,
            #"“While Mary is adjusting her ideas,” he continued, “let us return to Mr. Bingley.”"#,
            #"“I am sick of Mr. Bingley,” cried his wife."#,
            #"“I am sorry to hear _that_; but why did you not tell me so before? If I had known as much this morning, I certainly would not have called on him. It is very unlucky; but as I have actually paid the visit, we cannot escape the acquaintance now.”"#,
            #"The astonishment of the ladies was just what he wished--that of Mrs. Bennet perhaps surpassing the rest; though when the first tumult of joy was over, she began to declare that it was what she had expected all the while."#,
            #"“How good it was in you, my dear Mr. Bennet! But I knew I should persuade you at last. I was sure you loved your girls too well to neglect such an acquaintance. Well, how pleased I am! And it is such a good joke, too, that you should have gone this morning, and never said a word about it till now.”"#,
            #"“Now, Kitty, you may cough as much as you choose,” said Mr. Bennet; and, as he spoke, he left the room, fatigued with the raptures of his wife."#,
            #"“What an excellent father you have, girls,” said she, when the door was shut. “I do not know how you will ever make him amends for his kindness; or me either, for that matter. At our time of life, it is not so pleasant, I can tell you, to be making new acquaintances every day; but for your sakes we would do anything. Lydia, my love, though you _are_ the youngest, I dare say Mr. Bingley will dance with you at the next ball.”"#,
            #"“Oh,” said Lydia, stoutly, “I am not afraid; for though I _am_ the youngest, I’m the tallest.”"#,
            #"The rest of the evening was spent in conjecturing how soon he would return Mr. Bennet’s visit, and determining when they should ask him to dinner."#,
        ]),
        (title: #"CHAPTER III."#, paragraphs: [
            #"[Illustration"#,
            #"Not all that Mrs. Bennet, however, with the assistance of her five daughters, could ask on the subject, was sufficient to draw from her husband any satisfactory description of Mr. Bingley. They attacked him in various ways, with barefaced questions, ingenious suppositions, and distant surmises; but he eluded the skill of them all; and they were at last obliged to accept the second-hand intelligence of their neighbour, Lady Lucas. Her report was highly favourable. Sir William had been delighted with him. He was quite young, wonderfully handsome, extremely agreeable, and, to crown the whole, he meant to be at the next assembly with a large party. Nothing could be more delightful! To be fond of dancing was a certain step towards falling in love; and very lively hopes of Mr. Bingley’s heart were entertained."#,
            #"“If I can but see one of my daughters happily settled at Netherfield,” said Mrs. Bennet to her husband, “and all the others equally well married, I shall have nothing to wish for.”"#,
            #"In a few days Mr. Bingley returned Mr. Bennet’s visit, and sat about ten minutes with him in his library. He had entertained hopes of being admitted to a sight of the young ladies, of whose beauty he had heard much; but he saw only the father. The ladies were somewhat more fortunate, for they had the advantage of ascertaining, from an upper window, that he wore a blue coat and rode a black horse."#,
            #"An invitation to dinner was soon afterwards despatched; and already had Mrs. Bennet planned the courses that were to do credit to her housekeeping, when an answer arrived which deferred it all. Mr. Bingley was obliged to be in town the following day, and consequently unable to accept the honour of their invitation, etc. Mrs. Bennet was quite disconcerted. She could not imagine what business he could have in town so soon after his arrival in Hertfordshire; and she began to fear that he might always be flying about from one place to another, and never settled at Netherfield as he ought to be. Lady Lucas quieted her fears a little by starting the idea of his"#,
            #"being gone to London only to get a large party for the ball; and a report soon followed that Mr. Bingley was to bring twelve ladies and seven gentlemen with him to the assembly. The girls grieved over such a number of ladies; but were comforted the day before the ball by hearing that, instead of twelve, he had brought only six with him from London, his five sisters and a cousin. And when the party entered the assembly-room, it consisted of only five altogether: Mr. Bingley, his two sisters, the husband of the eldest, and another young man."#,
            #"Mr. Bingley was good-looking and gentlemanlike: he had a pleasant countenance, and easy, unaffected manners. His sisters were fine women, with an air of decided fashion. His brother-in-law, Mr. Hurst, merely looked the gentleman; but his friend Mr. Darcy soon drew the attention of the room by his fine, tall person, handsome features, noble mien, and the report, which was in general circulation within five minutes after his entrance, of his having ten thousand a year. The gentlemen pronounced him to be a fine figure of a man, the ladies declared he was much handsomer than Mr. Bingley, and he was looked at with great admiration for about half the evening, till his manners gave a disgust which turned the tide of his popularity; for he was discovered to be proud, to be above his company, and above being pleased; and not all his large estate in Derbyshire could save him from having a most forbidding, disagreeable countenance, and being unworthy to be compared with his friend."#,
            #"Mr. Bingley had soon made himself acquainted with all the principal people in the room: he was lively and unreserved, danced every dance, was angry that the ball closed so early, and talked of giving one himself at Netherfield. Such amiable qualities must speak for themselves. What a contrast between him and his friend! Mr. Darcy danced only once with Mrs. Hurst and once with Miss Bingley, declined being introduced to any other lady, and spent the rest of the evening in walking about the room, speaking occasionally to one of his own party. His character was decided. He was the proudest, most disagreeable man in the world, and everybody hoped that he would never come there again. Amongst the most violent against him was Mrs. Bennet, whose dislike of his general behaviour was sharpened into particular resentment by his having slighted one of her daughters."#,
            #"Elizabeth Bennet had been obliged, by the scarcity of gentlemen, to sit down for two dances; and during part of that time, Mr. Darcy had been standing near enough for her to overhear a conversation between him and Mr. Bingley, who came from the dance for a few minutes to press his friend to join it."#,
            #"“Come, Darcy,” said he, “I must have you dance. I hate to see you standing about by yourself in this stupid manner. You had much better dance.”"#,
            #"“I certainly shall not. You know how I detest it, unless I am particularly acquainted with my partner. At such an assembly as this, it would be insupportable. Your sisters are engaged, and there is not another woman in the room whom it would not be a punishment to me to stand up with.”"#,
            #"“I would not be so fastidious as you are,” cried Bingley, “for a kingdom! Upon my honour, I never met with so many pleasant girls in my life as I have this evening; and there are several of them, you see, uncommonly pretty.”"#,
            #"“_You_ are dancing with the only handsome girl in the room,” said Mr. Darcy, looking at the eldest Miss Bennet."#,
            #"“Oh, she is the most beautiful creature I ever beheld! But there is one of her sisters sitting down just behind you, who is very pretty, and I dare say very agreeable. Do let me ask my partner to introduce you.”"#,
            #"“Which do you mean?” and turning round, he looked for a moment at Elizabeth, till, catching her eye, he withdrew his own, and coldly said, “She is tolerable: but not handsome enough to tempt _me_; and I am in no humour at present to give consequence to young ladies who are slighted by other men. You had better return to your partner and enjoy her smiles, for you are wasting your time with me.”"#,
            #"Mr. Bingley followed his advice. Mr. Darcy walked off; and Elizabeth remained with no very cordial feelings towards him. She told the story, however, with great spirit among her friends; for she had a lively, playful disposition, which delighted in anything ridiculous."#,
            #"The evening altogether passed off pleasantly to the whole family. Mrs. Bennet had seen her eldest daughter much admired by the Netherfield party. Mr. Bingley had danced with her twice, and she had been distinguished by his sisters. Jane was as much gratified by this as her mother could be, though in a quieter way. Elizabeth felt Jane’s pleasure. Mary had heard herself mentioned to Miss Bingley as the most accomplished girl in the neighbourhood; and Catherine and Lydia had been fortunate enough to be never without partners, which was all that they had yet learnt to care for at a ball. They returned, therefore, in good spirits to Longbourn, the village where they lived, and of which they were the principal inhabitants. They found Mr. Bennet still up. With a book, he was regardless of time; and on the present occasion he had a good deal of curiosity as to the event of an evening which had raised such splendid expectations. He had rather hoped that all his wife’s views on the stranger would be disappointed; but he soon found that he had a very different story to hear."#,
            #"“Oh, my dear Mr. Bennet,” as she entered the room, “we have had a most delightful evening, a most excellent ball. I wish you had been there. Jane was so admired, nothing could be like it. Everybody said how well she looked; and Mr. Bingley thought her quite beautiful, and danced with her twice. Only think of _that_, my dear: he actually danced with her twice; and she was the only creature in the room that he asked a second time. First of all, he asked Miss Lucas. I was so vexed to see him stand up with her; but, however, he did not admire her at all; indeed, nobody can, you know; and he seemed quite struck with Jane as she was going down the dance. So he inquired who she was, and got introduced, and asked her for the two next. Then, the two third he danced with Miss King, and the two fourth with Maria Lucas, and the two fifth with Jane again, and the two sixth with Lizzy, and the _Boulanger_----”"#,
            #"“If he had had any compassion for _me_,” cried her husband impatiently, “he would not have danced half so much! For God’s sake, say no more of his partners. O that he had sprained his ancle in the first dance!”"#,
            #"“Oh, my dear,” continued Mrs. Bennet, “I am quite delighted with him. He is so excessively handsome! and his sisters are charming women. I never in my life saw anything more elegant than their dresses. I dare say the lace upon Mrs. Hurst’s gown----”"#,
            #"Here she was interrupted again. Mr. Bennet protested against any description of finery. She was therefore obliged to seek another branch of the subject, and related, with much bitterness of spirit, and some exaggeration, the shocking rudeness of Mr. Darcy."#,
            #"“But I can assure you,” she added, “that Lizzy does not lose much by not suiting _his_ fancy; for he is a most disagreeable, horrid man, not at all worth pleasing. So high and so conceited, that there was no enduring him! He walked here, and he walked there, fancying himself so very great! Not handsome enough to dance with! I wish you had been there, my dear, to have given him one of your set-downs. I quite detest the man.”"#,
            #"[Illustration"#,
        ]),
    ])
}
#endif
