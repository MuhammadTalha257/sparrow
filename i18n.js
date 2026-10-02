// Languages: English, Urdu, Hindi, Arabic. Screens are translated; typed/spoken commands in
// Roman Urdu / Hindi ("kal 5 baje yaad dilana…", "chrome kholo") are understood too.
import { store } from './store.js';

export const LANGS = { en: 'English', ur: 'اردو Urdu', hi: 'हिन्दी Hindi', ar: 'العربية Arabic' };
export const SPEECH_LANG = { en: 'en-GB', ur: 'ur-PK', hi: 'hi-IN', ar: 'ar-SA' };
const RTL = new Set(['ur', 'ar']);

const T = {
  en: {
    home: 'Home', chat: 'Chat', plan: 'Plan', memory: 'Memory', tools: 'Tools', settings: 'Settings', today: 'Today', seeAll: 'See all',
    quick: 'Quick', aiApps: 'AI apps', myDay: 'My day', talk: 'Talk', upNext: 'UP NEXT', checkIn: 'Check-in', ask: 'Ask Sparrow… e.g. remind me to call mum at 6pm',
    tasks: 'Tasks', meetings: 'Meetings', reminders: 'Reminders', notes: 'Notes', customers: 'Customers', money: 'Money', habits: 'Habits',
    prayer: 'Prayer times', nextPrayer: 'Next prayer', done: 'Done', later: 'Later', snooze: 'Snooze 10 min', search: 'Search your memory…',
    morning: 'Good morning', afternoon: 'Good afternoon', evening: 'Good evening', night: 'Good evening', noTasks: 'No tasks today', clear: 'Your day is clear',
    tasksLeft: 'tasks left today', allDone: 'All done today!', tickHint: 'Tick tasks as you go — I\'ll check in tonight.',
  },
  ur: {
    home: 'ہوم', chat: 'گفتگو', plan: 'منصوبہ', memory: 'یادداشت', tools: 'ٹولز', settings: 'ترتیبات', today: 'آج', seeAll: 'سب دیکھیں',
    quick: 'فوری', aiApps: 'اے آئی ایپس', myDay: 'میرا دن', talk: 'بات کریں', upNext: 'اگلا', checkIn: 'جائزہ', ask: 'اسپیرو سے پوچھیں… مثلاً کل 5 بجے یاد دلانا',
    tasks: 'کام', meetings: 'میٹنگز', reminders: 'یاد دہانیاں', notes: 'نوٹس', customers: 'گاہک', money: 'حساب', habits: 'عادتیں',
    prayer: 'نماز کے اوقات', nextPrayer: 'اگلی نماز', done: 'ہو گیا', later: 'بعد میں', snooze: '10 منٹ بعد', search: 'اپنی یادداشت میں تلاش کریں…',
    morning: 'صبح بخیر', afternoon: 'سہ پہر بخیر', evening: 'شام بخیر', night: 'السلام علیکم', noTasks: 'آج کوئی کام نہیں', clear: 'آج کا دن خالی ہے',
    tasksLeft: 'کام باقی ہیں', allDone: 'آج کے سب کام مکمل!', tickHint: 'کام مکمل کرتے جائیں — رات کو میں پوچھوں گا۔',
  },
  hi: {
    home: 'होम', chat: 'चैट', plan: 'योजना', memory: 'याददाश्त', tools: 'टूल्स', settings: 'सेटिंग्स', today: 'आज', seeAll: 'सब देखें',
    quick: 'झटपट', aiApps: 'एआई ऐप्स', myDay: 'मेरा दिन', talk: 'बात करें', upNext: 'आगे', checkIn: 'चेक-इन', ask: 'स्पैरो से पूछें… जैसे कल 5 बजे याद दिलाना',
    tasks: 'काम', meetings: 'मीटिंग', reminders: 'रिमाइंडर', notes: 'नोट्स', customers: 'ग्राहक', money: 'हिसाब', habits: 'आदतें',
    prayer: 'नमाज़ का समय', nextPrayer: 'अगली नमाज़', done: 'हो गया', later: 'बाद में', snooze: '10 मिनट बाद', search: 'अपनी याददाश्त में खोजें…',
    morning: 'सुप्रभात', afternoon: 'नमस्ते', evening: 'शुभ संध्या', night: 'नमस्ते', noTasks: 'आज कोई काम नहीं', clear: 'आज का दिन खाली है',
    tasksLeft: 'काम बाकी हैं', allDone: 'आज के सब काम पूरे!', tickHint: 'काम पूरे करते जाइए — रात को मैं पूछूँगा।',
  },
  ar: {
    home: 'الرئيسية', chat: 'محادثة', plan: 'الخطة', memory: 'الذاكرة', tools: 'أدوات', settings: 'الإعدادات', today: 'اليوم', seeAll: 'عرض الكل',
    quick: 'سريع', aiApps: 'تطبيقات الذكاء', myDay: 'يومي', talk: 'تحدث', upNext: 'التالي', checkIn: 'المراجعة', ask: 'اسأل سبارو… مثلاً ذكّرني غداً الساعة 5',
    tasks: 'المهام', meetings: 'الاجتماعات', reminders: 'التذكيرات', notes: 'الملاحظات', customers: 'العملاء', money: 'المال', habits: 'العادات',
    prayer: 'أوقات الصلاة', nextPrayer: 'الصلاة القادمة', done: 'تم', later: 'لاحقاً', snooze: 'بعد 10 دقائق', search: 'ابحث في ذاكرتك…',
    morning: 'صباح الخير', afternoon: 'مساء الخير', evening: 'مساء الخير', night: 'مرحباً', noTasks: 'لا مهام اليوم', clear: 'يومك فارغ',
    tasksLeft: 'مهام متبقية', allDone: 'أنجزت كل مهام اليوم!', tickHint: 'أنجز مهامك — سأراجع معك الليلة.',
  },
};

export function t(key) { const l = store.settings.lang || 'en'; return (T[l] && T[l][key]) || T.en[key] || key; }
export const lang = () => store.settings.lang || 'en';

export function applyI18n(root = document) {
  const l = lang();
  document.documentElement.lang = l;
  document.documentElement.dir = RTL.has(l) ? 'rtl' : 'ltr';
  root.querySelectorAll('[data-i18n]').forEach(el => { el.textContent = t(el.dataset.i18n); });
  root.querySelectorAll('[data-i18n-ph]').forEach(el => { el.placeholder = t(el.dataset.i18nPh); });
}

/** Turns common Roman Urdu / Hindi / Urdu / Hindi-script words into English so the brain understands. */
export function normalizeCommand(text) {
  let s = ' ' + text.trim() + ' ';
  const rules = [
    [/\s(yaad\s*dila(o|na|dena|do|yen|ana)|یاد\s*دلا\S*|याद\s*दिला\S*|ذكرني|ذكّرني)\s/gi, ' remind me '],
    [/\s(kal|کل|कल|غدا|غداً)\s/gi, ' tomorrow '],
    [/\s(aaj|aj|آج|आज|اليوم)\s/gi, ' today '],
    [/\s(parson|پرسوں|परसों)\s/gi, ' day after tomorrow '],
    [/\s(subah|صبح|सुबह)\s/gi, ' morning '],
    [/\s(shaam|sham|شام|शाम)\s/gi, ' evening '],
    [/\s(raat|رات|रात)\s/gi, ' night '],
    [/\s(\d{1,2})\s*(baje|بجے|बजे)\s/gi, ' at $1 '],
    [/\s(mausam|موسم|मौसम|الطقس)(\s(kaisa hai|کیسا ہے|कैसा है))?\s/gi, ' weather '],
    [/\s(namaz|نماز|नमाज़|नमाज|الصلاة)(\s(ka|ki|کا|کی|का|की)?\s?(waqt|time|اوقات|وقت|समय))?\s/gi, ' prayer times '],
    [/\s(time kya hai|waqt kya hai|ٹائم کیا ہے|समय क्या है|كم الساعة)\s/gi, ' what time is it '],
    [/\s(mujhe|mujhay|مجھے|मुझे)\s/gi, ' '],
    [/\s(karna|karni|کرنا|करना)\s/gi, ' '],
  ];
  for (const [re, rep] of rules) s = s.replace(re, rep);
  s = s.replace(/\s(ko|کو|को)\s/gi, ' ');
  // Urdu/Hindi put the verb last: "… remind me" → "remind me …"
  if (/\sremind me\s/.test(s) && !/^\s*remind me/.test(s)) s = ' remind me ' + s.replace(/\sremind me\s/, ' ');
  // "chrome kholo" / "کروم کھولو" / "क्रोम खोलो" → "open chrome"
  const open = s.trim().match(/^(.+?)\s+(kholo|khol\s*do|kholna|chalao|chala\s*do|کھولو|کھول\s*دو|چلاؤ|खोलो|खोल\s*दो|चलाओ|افتح)$/i);
  if (open) return 'open ' + open[1].trim();
  const play = s.trim().match(/^(.+?)\s+(lagao|laga\s*do|chalao|bajao|لگاؤ|بجاؤ|लगाओ|बजाओ)$/i);
  if (play) return 'play ' + play[1].trim();
  return s.replace(/\s+/g, ' ').trim();
}
