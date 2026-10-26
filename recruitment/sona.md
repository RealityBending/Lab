# SONA

How we put a study on **SONA**, the University of Sussex psychology participant pool, where students take part for
course credit: <https://sussexpsychology.sona-systems.com>. Sign in with the green "University of Sussex Log In" button
(the University's single sign-on), not the User ID and password boxes under it. Questions about the pool go to its
administrator, sona-admin@sussex.ac.uk.

Each project keeps the exact wording of its own SONA study (name, abstract, description, link) in its own recruitment
notes. This page is what is true of any study.

Our studies, past and present, are under **My Studies** (the old ones under its Inactive tab). A study's page is
`exp_info.aspx?experiment_id=<id>`, and **Copy Study** on it starts a new study from its settings. The most recent
example written out in full is the Abyss Test's (TestYourself, experiment 2102, October 2026), in
`TestYourself/data/collected/recruitment.md`.

## Setting one up

1. **Add New Study** asks for three things that **cannot be changed afterwards**: the type (Standard, at a time and
   place or over Zoom; **Online External**, a link to our own page, which is what an online study of ours is; Online
   Internal Survey, built inside SONA), the number of parts, and the compensation (credit, or paid).
2. **The form.** Every field is required unless marked optional. The limits are SONA's own (`maxlength`):

   | Field                    | Limit                  | Where it shows                                                           |
   | ------------------------ | ---------------------- | ------------------------------------------------------------------------ |
   | Study Name               | 100, **HTML included** | The list of studies, as its headline                                     |
   | Brief Abstract           | 255                    | The list, as the line under the name, after "(2 Credits) (Online Study)" |
   | Detailed Description     | none                   | The study's own page, once clicked                                       |
   | Eligibility Requirements | 245                    | The study's page                                                         |
   | Preparation              | 245                    | The study's page                                                         |
   | Ethics Approval Code     | 50                     | The study's page                                                         |
   | Study URL                | 200                    | Given to a participant only once they have signed up                     |

   Credits follow the scheme's conversion, which is 2 credits for a 30-minute study. The age restriction (Yes, 18 to
   99) enforces the usual "18 or over" off the date of birth participants give SONA.
3. **Online External studies.** Put `%SURVEY_CODE%` in the Study URL (e.g. `…/?pid=%SURVEY_CODE%&source=SONA`): SONA
   replaces it with the participant's code, and answer Yes to identifying participants by a random code only. Once the
   study is saved, its page shows two **completion URLs** carrying that code: the client-side one, opened by the
   participant's browser at the end of the study, grants the credit there and then with nobody marking it by hand.
   Our page has to send people to it with their code on the end. "Study URL Display: Yes" keeps the link visible after
   taking part, for studies people may come back to.
4. **Researchers** are picked from SONA's own list, which holds only people with a researcher account on it. Students
   on a project usually have none: ask the administrator for one, or name them in the description instead.
5. **Saving does not publish.** A new study is *not approved* and, unless set otherwise, *inactive*. Nobody sees it
   until:
   - it has a **timeslot**: an online study needs one too ("Online studies require a timeslot so that participants can
     sign up"). For an online study it is **a single timeslot** (View/Administer Time Slots → Add A Timeslot) whose
     three fields are the final participation date, its time, and the maximum number of participants, so it is the
     study's closing date and its number of places; its Modify link changes either later. The list goes on saying
     "No Available Timeslots" until the study is active and approved;
   - **Active Study** is Yes;
   - **Send Request** on its page has gone to the administrator, and they have approved it.

## The name is the advert

The list of studies is long (well over a hundred in October 2026), and a name is all most students read of it. A
study is chosen from that list or not at all, so the name is worth more thought than anything else on the form.

### The listing order

**SONA says participants see the list in random order**, under the Study Name box and at the foot of the list. What
*is* in a fixed order is the list researchers and the administrator see, sorted by **Study Name** (the default) or by
Last Activity Date, and that is where the names starting with `!!!` sit at the top. Whether the participants' list is
as random as SONA says has not been checked from a participant's account; until it is, prefixing a name costs little.

The name is sorted **as typed, tags and all**, in this order of first characters (read off the 106 approved studies
and checked with test names in My Studies, October 2026):

```
whitespace  <  !  <  (  <  *  <  [  <  £  <  <  (any HTML tag)  <  digits  <  letters
```

So:

- **A space between exclamation marks beats none**: `! ! ! !` sorts before `!!!!!!`, which is why the top of the list
  is spaced. The next `! ` added wins, and so on.
- **A name that opens with a tag sinks** below everything starting with a bracket, an asterisk or "£". Anything put in
  front to lift it goes before the tags.
- **A leading `&nbsp;`, typed as those six characters, beats every `!`.** SONA stores it as a non-breaking space,
  which sorts as whitespace, before `!`. The other ways in fail: a non-breaking space pasted as the character itself
  is stripped on saving (a plain space surely is too), and `\` and `~` are kept but sort after `!` (and before the
  tags).
- **The `&nbsp;` is lost on the next edit.** The edit form shows it as the character, which saving then strips: saving
  the form once without changing anything dropped it (checked). So **type `&nbsp;` again every time the study is
  changed**, and check in My Studies that it still sorts first. It also takes 6 of the 100 characters.
- **It is an arms race.** Once others copy it, the character after the space decides (`&nbsp;!` before `&nbsp;A`), and
  the administrator may not like any of it.

### What stands out

Whatever the order, how a name looks and what it promises is what gets it read:

- **Colour and bold.** HTML works in the name. Most names are plain grey-blue text, so one coloured word in bold is
  seen before anything is read. Colour the hook, not the credits.
- **A hook, not a method.** Most names describe the study the way the ethics application does ("Investigating the
  relationship between individual differences and CBM-I training"). A question or something the participant gets
  stands out among them: "Can AI Read Your Emotions?", "Beat the algorithm", "Test your reflexes", "Do I want to
  know?". Ours leads with "Do you know yourself?", with the results promised in the abstract.
- **The reward and the time.** Students compare credits per minute, so most names say them, in brackets or after a
  `|`. SONA already prints "(2 Credits)" under the name, so when room is short these go before the hook does.
- **The abstract is the second line.** It is shown in the list under the name, so its first words are read too. HTML
  works there as well, so the promise can be picked out the way the hook is (ours: "A **fun** and science-based
  personality test that **shows your results!**", in bold crimson and green, so as not to repeat the name's purple).
- **Stay within what ethics approved.** The name and description may be checked against the advert in the
  application: rephrase it to be appealing, but do not promise anything it does not say.

**The 100 characters include the tags, and SONA rewrites a `style` before it counts.** `<b style="color:#7b1fa2">`
is saved as `<b style="color: rgba(123, 31, 162, 1)">`, 41 characters, and whatever no longer fits is **cut off
without a warning**: our first save lost its "| 2 credits" that way. A `<font>` tag is kept exactly as typed, so it is
the cheaper way to colour a name:

```
&nbsp;<b><font color="purple">Do you know yourself?</font></b> The Abyss Test | 25min online 2 cred
```

That is 35 characters of tags, and 6 more for the `&nbsp;` (see **The listing order**), leaving 59 for the words,
which is tight: this one is 99 characters, after trying versions that dropped the "The" or wrote "2 credits" in full.
Count before saving. A named colour (`purple`, `teal`, `crimson`, `darkorange`,
`royalblue`) is shorter than a hex code and reads well on SONA's white. After saving, look at the study's page to check
that the whole name came through.

The lab's names so far follow one pattern, the hook coloured and the practical part after a bar:

```
<b style="color: rgba(76, 175, 80, 1)">Test your reflexes</b> |<b> 30min online</b> | 2 credits
<b style="color: rgba(216, 27, 96, 1)">Are you aroused by AI images?</b> | 30min online (2 credits)
<b style="color: rgba(57, 73, 171, 1)">Questionnaires about your Mood</b> | 10min online (1 credit)
2 Credits | <b style="color: rgba(0, 81, 255, 1)"> Questionnaires about your body!</b>
```
