import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/context_x.dart';
import '../../core/widgets/app_icons.dart';

/// The version people agree to at sign-up (stored in their account metadata).
/// Change it whenever the Terms or Privacy Policy change in a meaningful way.
const legalVersion = '2026-10-04';
const _effective = '4 October 2026';

enum LegalDoc {
  terms('terms', 'Terms of Service'),
  privacy('privacy', 'Privacy Policy'),
  guidelines('guidelines', 'Community Guidelines');

  const LegalDoc(this.slug, this.title);

  final String slug;
  final String title;

  static LegalDoc? fromSlug(String? slug) => values.where((d) => d.slug == slug).firstOrNull;

  String get route => '/legal/$slug';
}

/// One legal page. Paragraphs starting with "• " are shown as bullet points.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.doc});

  final LegalDoc? doc;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final doc = this.doc;
    final sections = switch (doc) {
      LegalDoc.terms => _terms,
      LegalDoc.privacy => _privacy,
      LegalDoc.guidelines => _guidelines,
      null => const <(String, List<String>)>[],
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(AppIcons.back),
          onPressed: () => context.canPop() ? context.pop() : context.go('/welcome'),
        ),
        title: Text(doc?.title ?? 'Not found'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.xxxl + context.safePadding.bottom),
        children: [
          Text('Effective $_effective', style: context.text.bodySmall),
          for (final (heading, paragraphs) in sections) ...[
            const SizedBox(height: Space.xl),
            Text(heading, style: context.text.titleMedium),
            for (final paragraph in paragraphs)
              Padding(
                padding: const EdgeInsets.only(top: Space.sm),
                child: paragraph.startsWith('• ')
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 8, right: 10, left: 4),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(color: c.inkMuted, shape: BoxShape.circle),
                            ),
                          ),
                          Expanded(
                            child: Text(paragraph.substring(2), style: context.text.bodyMedium!.copyWith(height: 1.5)),
                          ),
                        ],
                      )
                    : Text(paragraph, style: context.text.bodyMedium!.copyWith(height: 1.5)),
              ),
          ],
          if (doc != null) ...[
            const SizedBox(height: Space.xxl),
            Wrap(
              spacing: Space.lg,
              children: [
                for (final other in LegalDoc.values.where((d) => d != doc))
                  TextButton(onPressed: () => context.pushReplacement(other.route), child: Text(other.title)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

const _terms = <(String, List<String>)>[
  (
    'Welcome to Quad',
    [
      'Quad is a community app for students: communities, posts, chat, rooms with voice and video, events, reels, '
          'playlists and college rankings. These Terms are an agreement between you and the people who run Quad '
          '("we"). By creating an account or using Quad, you agree to them, to our Privacy Policy and to our '
          'Community Guidelines.',
    ],
  ),
  (
    'Who can use Quad',
    [
      '• You must be at least 13 years old. If you are under 18, you need permission from a parent or guardian.',
      '• You may have one personal account. Don\'t create accounts for other people or pretend to be someone else.',
      '• Give accurate information about yourself, such as your name and college.',
    ],
  ),
  (
    'Your account',
    [
      'You are responsible for what happens on your account. Keep your password private and tell us if you think '
          'someone else has used it. We may suspend or remove accounts that break these Terms or our Community '
          'Guidelines, or when the law requires it.',
    ],
  ),
  (
    'Your content',
    [
      'You own what you post: posts, comments, messages, photos, videos, reels, stickers you send and events you '
          'create. To run Quad we need permission to store it, show it to the people you share it with, and make '
          'copies for backups and moderation. You give us that permission, worldwide and free of charge, for as long '
          'as your content is on Quad. It ends when you delete the content, except for copies we must keep for '
          'safety, legal or backup reasons for a limited time.',
      'Only post things you have the right to share. Don\'t post other people\'s work, photos of people who haven\'t '
          'agreed, or anything that breaks the law.',
    ],
  ),
  (
    'Anonymous posting and private profiles',
    [
      'You can post in communities, comment and message in rooms under a random anonymous name, and private profiles '
          'do so automatically. Other students and community staff can\'t see who you are. We still store who wrote '
          'every post so we can enforce these Terms, act on serious reports and respond to valid legal requests. '
          'Anonymity is not a licence to break the rules.',
    ],
  ),
  (
    'Communities, roles and moderation',
    [
      'Community owners and the people they give roles to can edit their community, manage rooms and events, '
          'remove posts and messages, and remove or ban members, within the permissions of their role. They must use '
          'these tools fairly and in line with our Community Guidelines. We can review, reverse or override their '
          'decisions, and we can act on any content or account on Quad.',
    ],
  ),
  (
    'Calls',
    [
      'Voice and video calls are carried by our calling provider so they work on any network. Quad does not record '
          'calls. Don\'t record, screenshot or share a call without the agreement of everyone in it.',
    ],
  ),
  (
    'Events',
    [
      'Events are organised by students and communities, not by Quad. The organiser is responsible for the event, '
          'its safety and anything that happens there. Registering through Quad doesn\'t make us a party to any '
          'arrangement between you and the organiser.',
    ],
  ),
  (
    'College rankings',
    [
      'Rankings on Quad are calculated from activity on Quad, such as active members, events and discussions. They '
          'are not a measure of academic quality, placements or accreditation, and you shouldn\'t rely on them as '
          'such. "How rankings work" explains the method.',
    ],
  ),
  (
    'Things you must not do',
    [
      '• Break the law, or help anyone else do so.',
      '• Harass, threaten, bully or impersonate anyone, or try to find out who is behind an anonymous name.',
      '• Post sexual content involving anyone under 18. We report it to the authorities.',
      '• Send spam, scams or malware, or use bots or scripts to post, follow or message.',
      '• Try to get into accounts, data or parts of Quad you aren\'t allowed to, or disrupt the service.',
      '• Sell, leak or share exam papers, graded work or other academic misconduct material.',
    ],
  ),
  (
    'Ending your use of Quad',
    [
      'You can stop using Quad at any time and ask us to delete your account. We may suspend or end your access if '
          'you break these Terms, if we must for legal reasons, or if we stop offering Quad.',
    ],
  ),
  (
    'No guarantees',
    [
      'We work hard to keep Quad running and safe, but we provide it "as is". We can\'t promise it will always be '
          'available or free of errors, and we aren\'t responsible for what students post or for events organised '
          'by others. To the extent the law allows, our responsibility to you is limited to the amount you paid us '
          'for Quad in the last 12 months (Quad is currently free).',
    ],
  ),
  (
    'Changes to these Terms',
    [
      'We may update these Terms as Quad changes. If a change is significant we\'ll tell you in the app before it '
          'takes effect. If you keep using Quad after that, you accept the new Terms.',
    ],
  ),
  (
    'Questions and complaints',
    [
      'Report content or accounts with the Report option on any post, comment, message or profile. For anything '
          'else, contact the Quad team through the details on our app store listing.',
    ],
  ),
];

const _privacy = <(String, List<String>)>[
  (
    'In short',
    [
      'We collect what we need to run Quad, show your content to the people you choose, and keep the community '
          'safe. We don\'t sell your personal data and we don\'t show you third-party ads.',
    ],
  ),
  (
    'What we collect',
    [
      '• Account: your email address and password. Passwords are stored only as a secure hash.',
      '• Profile: name, username, photo, bio, college, department, year, skills, interests, achievements, and '
          'whether your profile is private.',
      '• Content: posts, comments, messages, photos, videos, reels, files, stickers you send, events you create, '
          'and the playlists you make.',
      '• Activity: who you follow and block, communities you join and your roles in them, reactions, saves, poll '
          'votes, event registrations, views and reports you make.',
      '• Calls: who joined which call and when. The audio and video pass through our calling provider and are not '
          'recorded or stored by Quad.',
      '• Technical: when you were last active, and basic device and network information our providers receive '
          'when the app connects to them (such as your IP address).',
    ],
  ),
  (
    'How we use it',
    [
      '• To run Quad: show your profile, posts and messages, deliver notifications, connect calls, and build your '
          'feeds and suggestions.',
      '• To keep Quad safe: enforce our rules, stop spam and abuse, review reports, and investigate misuse.',
      '• To calculate college rankings from activity totals. Rankings use counts, never individual profiles.',
      '• To meet legal obligations and respond to valid legal requests.',
    ],
  ),
  (
    'Who can see what',
    [
      '• Public profile: signed-in students can see your profile, posts on your profile, followers and the events '
          'you\'re attending.',
      '• Private profile: people you don\'t follow see only your name and photo. You don\'t appear online, and your '
          'community posts, comments and room messages show a random anonymous name.',
      '• Anonymous content: other students and community staff can\'t see who wrote it. We keep the link to your '
          'account so we can enforce our rules and respond to legal requests.',
      '• Private communities: posts, rooms and member lists are visible to members only.',
      '• Direct and group chats: visible only to the people in them. Chat files are stored privately and shared '
          'through links that expire.',
      '• People you block can\'t see your profile or content, follow you, message you or call you.',
    ],
  ),
  (
    'Who we share it with',
    [
      'We don\'t sell personal data. We share it only with service providers that help run Quad, under contracts '
          'that limit how they can use it: Supabase (database, sign-in, file storage and real-time updates) and '
          'LiveKit (voice and video calls). We may also share information when the law requires it, or to protect '
          'someone from serious harm.',
    ],
  ),
  (
    'How long we keep it',
    [
      'Your content stays until you delete it or your account is deleted. When you delete a post, comment or '
          'message it disappears from Quad straight away; we may keep a copy for a limited time for safety and in '
          'backups. We may keep records about reports and moderation decisions for longer to keep the community safe.',
    ],
  ),
  (
    'Your choices and rights',
    [
      '• Edit your profile, switch to a private profile, and delete your posts, comments and messages at any time.',
      '• Choose to post, comment or message anonymously.',
      '• Block people and leave communities.',
      '• Ask us for a copy of your data, to correct it, or to delete your account. Depending on where you live '
          '(for example under India\'s Digital Personal Data Protection Act), you may have further rights, including '
          'the right to complain to a regulator.',
    ],
  ),
  (
    'Children',
    [
      'Quad is not for children under 13. If you are under 18, you need permission from a parent or guardian. If '
          'we learn that a child under 13 has an account, we will delete it.',
    ],
  ),
  (
    'Security',
    [
      'Your data is protected by access rules in our database, so the app can only read and change what you\'re '
          'allowed to. Connections are encrypted. No system is perfectly secure, so please use a strong, unique '
          'password.',
    ],
  ),
  (
    'Changes and contact',
    [
      'We\'ll tell you in the app before significant changes to this policy take effect. For privacy questions or '
          'requests, contact the Quad team through the details on our app store listing.',
    ],
  ),
];

const _guidelines = <(String, List<String>)>[
  (
    'Quad is for students',
    [
      'Communities work when people feel safe to ask questions, share work and disagree respectfully. These '
          'guidelines apply everywhere on Quad: posts, comments, chats, rooms, calls, reels and events.',
    ],
  ),
  (
    'Be kind',
    [
      '• No harassment, bullying, threats or targeted insults, including in DMs and calls.',
      '• No hate: don\'t attack people for their caste, religion, race, ethnicity, gender, sexuality, disability, '
          'region or language.',
      '• Disagree with ideas, not people.',
    ],
  ),
  (
    'Respect privacy and anonymity',
    [
      '• Don\'t try to work out, guess or reveal who is behind an anonymous name.',
      '• Don\'t share someone\'s phone number, address, photos or private messages without their permission.',
      '• Don\'t record or screenshot calls without everyone\'s agreement.',
    ],
  ),
  (
    'Keep it safe',
    [
      '• No sexual content involving anyone under 18, ever. We remove it and report it.',
      '• No sexually explicit or graphic violent content.',
      '• No content that encourages self-harm. If you\'re struggling, please reach out to someone you trust or a '
          'local helpline.',
      '• No illegal goods, weapons or drugs.',
    ],
  ),
  (
    'Keep it honest',
    [
      '• No spam, scams, fake giveaways or misleading links.',
      '• Don\'t impersonate other students, staff, colleges or clubs.',
      '• No academic misconduct: don\'t sell or share exam papers, graded work or answers to live assessments.',
      '• Events must be real, and their details accurate.',
    ],
  ),
  (
    'For community staff',
    [
      '• Use your role\'s powers fairly and only for the community\'s benefit.',
      '• Explain removals where you can, and don\'t punish people for disagreeing with you.',
      '• Only give roles to people you trust, and only the permissions they need.',
    ],
  ),
  (
    'If something\'s wrong',
    [
      'Use Report on the post, comment, message, profile or community. Community staff review reports in their '
          'community; we review the rest and serious cases. Breaking these guidelines can lead to content being '
          'removed, a ban from a community, or your Quad account being suspended or removed.',
    ],
  ),
];
