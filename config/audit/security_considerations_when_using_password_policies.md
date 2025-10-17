I have a question regarding the hardening of a computer system by enforcing a timed rotation policy on passwords: Does this really improve the security? Because when enforcing such a policy, users tend to use post-its to write their passwords down, which increases the risk of a security breach. Could you provide me the sources for your answers, please?


## ChatGPT Answer

That’s a very good and subtle question — the answer is: **“it depends”**, but in many realistic settings a forced periodic password‑rotation policy (e.g. change every 60 / 90 days) can *hurt* security more than it helps, if not done carefully. Below I'll explain the logic, tradeoffs, and evidence (with sources).

---

## The theoretical justification for periodic password rotation

The usual arguments in favor of periodic password rotation are:

1. **Limit exposure time**
   If a password was compromised at some point (e.g. leaked, phished, or cracked offline but not yet used), rotating it ensures that even undetected breaches are “remedied” after some window.

2. **Reduce “stale” credentials**
   Over time, credentials might become more vulnerable (e.g. reused elsewhere, in old logs, etc.). Changing them occasionally may force users or systems to “refresh” security posture.

3. **Compliance / audit expectations**
   Some regulations or legacy security frameworks expect maximum password ages or rotation. (Though many modern frameworks are relaxing this.)

Those are plausible arguments in the abstract. But whether they actually deliver net benefit depends on how users and defenders behave in practice.

---

## The usability–security tradeoffs and human behavior pitfalls

In practice, forcing frequent password changes introduces significant user burden and predictable behavior, which adversaries can exploit. Some of the main problems are:

* **Predictable changes**
  Users often make *small, systematic modifications* to their old password (e.g. increment a number, append a character, rotate a known suffix). Attackers who know or have seen an old password can often guess the “new” one via simple transformations.
  The NIST guidelines explicitly mention this as a drawback. ([NIST Pages][1])

* **Easier (or more frequent) reuse across accounts**
  Because users are pressured to “manage many changing passwords,” they may reuse passwords across services to reduce cognitive load. This defeats much of the purpose of unique credentials.

* **Writing passwords down / insecure storage**
  When passwords are harder to remember (due to frequent changes), users may resort to writing them on post‑it notes, sticky notes, paper, text files, spreadsheets, etc. That creates a tangible, physical risk (someone sees the note, room is breached, etc.). Several sources mention this risk, particularly in the context of rotation policies. ([ManageEngine][2])

* **Help‑desk burden and resets**
  Increased frequency of password changes tends to drive up the number of calls to help desks for resets (forgotten passwords, lockouts, confusion). That is a nontrivial operational cost and risk (if resets are abused or social‑engineered). ([mm-ais.com][3])

* **False sense of security / distraction**
  Frequent rotation can give a false sense of safety that one is “doing security,” even though core risks (e.g. weak passwords, phishing, credential reuse) remain unaddressed.

* **Attack window often very short**
  In many real attacks, if an attacker gets a valid credential, they exploit it quickly—not many days or weeks later. Thus rotating every 90 days may not stop much, because the attacker acts before the next rotation. Some commentary argues that periodic rotation cannot keep pace with rapid exploitation. ([Clutch Security][4])

Thus, the intended protective effect may be undermined or reversed by user behavior and operational overhead.

---

## Recent guidance and shifts in best practice

Because of the practical tradeoffs, many leading standards and authorities have revised their stance on forced periodic password changes. Key points include:

* **NIST SP 800‑63B** (Digital Identity Guidelines) now **recommends not requiring** default periodic password changes (i.e. “arbitrary” expiration). Instead, it advises changing only upon evidence of compromise. ([NIST Pages][5])
  Specifically:

  > “Verifiers SHALL NOT require memorized secrets to be changed arbitrarily (e.g., periodically). However, verifiers SHALL force a change if there is evidence of compromise.” ([NIST Pages][1])

* Many commentary and security blogs echo that shift, pointing out how frequent forced changes lead to weaker security practices (reuse, writing down, predictable patterns). ([TechRadar][6])

* Some older or regulatory frameworks may still require maximum password age policies; in those cases, organizations may need to justify or provide compensating controls (strong password strength, detection of compromise, multi-factor authentication). (I don’t have a single canonical source for all regulatory domains, because many differ by industry/country.)

So the movement is toward *evidence‑based or risk‑based rotation*, rather than blind periodic rotation.

---

## When periodic rotation *does* still make sense (or is tolerable)

Periodic rotation isn’t always useless. There are scenarios where it can still offer value (or be acceptable), provided the implementation is careful and the drawbacks mitigated:

* **High‑sensitivity / privileged accounts**
  For accounts with elevated privileges (admins, root, service accounts, critical infrastructure), a rotation policy (perhaps at more frequent intervals) plus stringent controls can make sense, especially if combined with automation and auditing.

* **Legacy systems or constrained environments**
  In environments that lack more modern detection, monitoring, or identity tools, rotation may provide some guard in lieu of better alternatives.

* **Where periodic rotation is mandated by regulation or contract**
  If a compliance regime explicitly requires maximum password age, you may have to adopt it (though you should assess whether the requirement is up to date or whether alternative controls are accepted).

* **Rotation of non‑user secrets / credentials**
  The concept of rotating keys, API secrets, certificates, tokens is still broadly recommended (for secret management). But even there, the rotation needs to be done carefully (automated, with dependency propagation, monitoring, etc.) so as to not break systems and introduce human error. Some of the pitfalls are similar (managing dependencies, synchronizing changes, breaking hardcoded credentials). ([Clutch Security][7])

* **Longer maximum intervals**
  Some organizations compromise by making expiry rare (e.g. once per year) rather than quarterly.

* **With strong detection / breach monitoring**
  If your environment has good detection of compromised credentials (intrusion detection, anomaly detection, logging, etc.), you can rely more on “change on incident” policies.

So periodic rotation is not inherently “bad,” but in many user-facing contexts it becomes counterproductive unless accompanied by supporting controls.

---

## Net assessment: does a timed rotation improve security (in practice)?

Given the tradeoffs and evidence, my assessment is:

* If the rotation interval is short (e.g. 60 or 90 days), and the organization has no strong compensating mechanisms (monitoring, MFA, password strength enforcement), the rotation policy is likely to **reduce overall security** (because users adopt weaker practices or write things down).

* If you rotate infrequently (say annually) or only on evidence of compromise, with good monitoring, multi-factor authentication, user education, and strong password policies, then rotation can be a modest complementary control, but not a primary guarantee.

* In many modern environments, **the marginal benefit** of periodic password change (against many threats) is small compared to investments in **detection, anomaly monitoring, MFA**, etc.

* Importantly, the human factor dominates: if users are forced into insecure coping strategies (writing down passwords, reusing, choosing predictable modifications), you may get worse security than with no rotation.

In sum, timed rotation *can* help in some contexts, but as a blanket policy for human users it often backfires unless you are very careful with implementing supportive controls and minimizing user burden.

---

[1]: https://pages.nist.gov/800-63-FAQ/?utm_source=chatgpt.com "NIST SP 800-63 Digital Identity Guidelines-FAQ"
[2]: https://www.manageengine.com/products/passwordmanagerpro/password-rotation.html?utm_source=chatgpt.com "Password Rotation - Necessity, Pros and Cons, Best practices | Password Manager Pro"
[3]: https://mm-ais.com/blog/the_hidden_costs_of_password_expiration_policies_a_2024_anal.php?utm_source=chatgpt.com "mm-ais.com"
[4]: https://www.clutch.security/blog/why-rotation-hurts-security?utm_source=chatgpt.com "Rotation Creates a False Sense of Security: Why It’s an Unnecessary Evil"
[5]: https://pages.nist.gov/800-63-4/sp800-63b.html?utm_source=chatgpt.com "NIST Special Publication 800-63B"
[6]: https://www.techradar.com/pro/navigating-nists-updated-password-rotation-guidelines?utm_source=chatgpt.com "Navigating NIST’s updated password rotation guidelines | TechRadar"
[7]: https://www.clutch.security/blog/stop-rotating-secrets-how-frequent-key-changes-undermine-modern-security?utm_source=chatgpt.com "Stop Rotating Secrets: How Frequent Key Changes Undermine Modern Security"
