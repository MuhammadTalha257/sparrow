// Every country Zuffi can be set to, with its currency — and the features that matter there.
// Names come from the browser (in the user's language); currency symbols from Intl.
const RAW = 'AD:EUR AE:AED AF:AFN AG:XCD AI:XCD AL:ALL AM:AMD AO:AOA AR:ARS AS:USD AT:EUR AU:AUD AW:AWG AX:EUR AZ:AZN BA:BAM BB:BBD BD:BDT BE:EUR BF:XOF BG:BGN BH:BHD BI:BIF BJ:XOF BL:EUR BM:BMD BN:BND BO:BOB BQ:USD BR:BRL BS:BSD BT:BTN BW:BWP BY:BYN BZ:BZD CA:CAD CD:CDF CF:XAF CG:XAF CH:CHF CI:XOF CK:NZD CL:CLP CM:XAF CN:CNY CO:COP CR:CRC CU:CUP CV:CVE CW:ANG CY:EUR CZ:CZK DE:EUR DJ:DJF DK:DKK DM:XCD DO:DOP DZ:DZD EC:USD EE:EUR EG:EGP EH:MAD ER:ERN ES:EUR ET:ETB FI:EUR FJ:FJD FK:FKP FM:USD FO:DKK FR:EUR GA:XAF GB:GBP GD:XCD GE:GEL GF:EUR GG:GBP GH:GHS GI:GIP GL:DKK GM:GMD GN:GNF GP:EUR GQ:XAF GR:EUR GT:GTQ GU:USD GW:XOF GY:GYD HK:HKD HN:HNL HR:EUR HT:HTG HU:HUF ID:IDR IE:EUR IL:ILS IM:GBP IN:INR IQ:IQD IR:IRR IS:ISK IT:EUR JE:GBP JM:JMD JO:JOD JP:JPY KE:KES KG:KGS KH:KHR KI:AUD KM:KMF KN:XCD KP:KPW KR:KRW KW:KWD KY:KYD KZ:KZT LA:LAK LB:LBP LC:XCD LI:CHF LK:LKR LR:LRD LS:LSL LT:EUR LU:EUR LV:EUR LY:LYD MA:MAD MC:EUR MD:MDL ME:EUR MF:EUR MG:MGA MH:USD MK:MKD ML:XOF MM:MMK MN:MNT MO:MOP MP:USD MQ:EUR MR:MRU MS:XCD MT:EUR MU:MUR MV:MVR MW:MWK MX:MXN MY:MYR MZ:MZN NA:NAD NC:XPF NE:XOF NF:AUD NG:NGN NI:NIO NL:EUR NO:NOK NP:NPR NR:AUD NU:NZD NZ:NZD OM:OMR PA:PAB PE:PEN PF:XPF PG:PGK PH:PHP PK:PKR PL:PLN PM:EUR PR:USD PS:ILS PT:EUR PW:USD PY:PYG QA:QAR RE:EUR RO:RON RS:RSD RU:RUB RW:RWF SA:SAR SB:SBD SC:SCR SD:SDG SE:SEK SG:SGD SH:SHP SI:EUR SK:EUR SL:SLE SM:EUR SN:XOF SO:SOS SR:SRD SS:SSP ST:STN SV:USD SX:ANG SY:SYP SZ:SZL TC:USD TD:XAF TG:XOF TH:THB TJ:TJS TK:NZD TL:USD TM:TMT TN:TND TO:TOP TR:TRY TT:TTD TV:AUD TW:TWD TZ:TZS UA:UAH UG:UGX US:USD UY:UYU UZ:UZS VA:EUR VC:XCD VE:VES VG:USD VI:USD VN:VND VU:VUV WF:XPF WS:WST XK:EUR YE:YER YT:EUR ZA:ZAR ZM:ZMW ZW:USD';
export const CURRENCY = Object.fromEntries(RAW.split(' ').map(p => p.split(':')));
const dn = (() => { try { return new Intl.DisplayNames([navigator.language || 'en', 'en'], { type: 'region' }); } catch { return null; } })();
export const name = code => code === 'OTHER' ? 'Another country' : (dn?.of(code) || code);
export const flag = code => code && code.length === 2 ? String.fromCodePoint(...[...code.toUpperCase()].map(c => 0x1F1E6 + c.charCodeAt(0) - 65)) : '🌍';
/** All countries, sorted by name. */
export const all = () => Object.keys(CURRENCY).map(c => ({ code: c, name: name(c), flag: flag(c) })).sort((a, b) => a.name.localeCompare(b.name));
/** "Rs", "£", "$", "AED"… for a country. */
export function symbol(code) {
  const c = CURRENCY[code]; if (!c) return '$';
  if (c === 'PKR' || c === 'LKR' || c === 'NPR') return 'Rs';
  try {
    const p = new Intl.NumberFormat('en', { style: 'currency', currency: c, currencyDisplay: 'narrowSymbol' }).formatToParts(1).find(x => x.type === 'currency');
    return p?.value || c;
  } catch { return c; }
}
/** Best guess from the phone / computer settings. */
export function guess() {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone || '';
  const lang = (navigator.language || '').split('-')[1];
  if (/Karachi/.test(tz)) return 'PK';
  if (/London|Belfast/.test(tz)) return 'GB';
  if (/Dubai/.test(tz)) return 'AE';
  if (/Riyadh/.test(tz)) return 'SA';
  if (/Kolkata|Calcutta/.test(tz)) return 'IN';
  return lang && CURRENCY[lang] ? lang : '';
}

// Markets where business happens on WhatsApp (groups, voice notes, Roman script).
const WA_HEAVY = new Set(['PK', 'IN', 'BD', 'AE', 'SA', 'QA', 'KW', 'OM', 'BH', 'NG', 'KE', 'GH', 'ZA', 'EG', 'MA', 'ID', 'MY', 'BR', 'MX', 'AR', 'CO', 'TR', 'ES', 'IT', 'LK', 'NP']);
const PORTALS = {
  PK: ['Zameen.com', 'Graana', 'OLX', 'Facebook', 'WhatsApp'], IN: ['99acres', 'MagicBricks', 'Housing.com', 'NoBroker', 'WhatsApp'],
  GB: ['Rightmove', 'Zoopla', 'OnTheMarket', 'Checkatrade', 'Google', 'Facebook'], AE: ['Bayut', 'Property Finder', 'Dubizzle', 'WhatsApp'],
  SA: ['Aqar', 'Bayut', 'Haraj', 'WhatsApp'], US: ['Zillow', 'Realtor.com', 'Redfin', 'Google', 'Facebook'], CA: ['Realtor.ca', 'Kijiji', 'Google'],
  AU: ['realestate.com.au', 'Domain', 'Google'], BD: ['Bproperty', 'Bikroy', 'Facebook', 'WhatsApp'],
};
const PAY = {
  PK: ['Cash', 'Bank', 'JazzCash', 'Easypaisa', 'Cheque'], IN: ['UPI', 'Cash', 'Bank', 'Card'], BD: ['bKash', 'Nagad', 'Cash', 'Bank'],
  KE: ['M-Pesa', 'Cash', 'Bank'], AE: ['Card', 'Cash', 'Bank transfer', 'Cheque'], GB: ['Card', 'Cash', 'Bank transfer', 'Online'],
};

/** What Zuffi switches on for a country. */
export function features(code) {
  const pk = code === 'PK', gb = code === 'GB', south = ['PK', 'IN', 'BD', 'NP', 'LK'].includes(code);
  return {
    code, gb, pk,
    sizeUnit: pk ? 'marla / kanal' : south ? 'sq ft / marla' : ['US', 'GB', 'CA'].includes(code) ? 'sq ft' : 'm²',
    portals: PORTALS[code] || ['Google', 'Facebook', 'Instagram', 'WhatsApp', 'Website'],
    methods: PAY[code] || ['Card', 'Cash', 'Bank transfer'],
    groupListings: WA_HEAVY.has(code),           // turn WhatsApp group posts into stock
    voiceNotes: true,
    commissionSplits: true,
    installments: south || ['AE', 'SA', 'EG', 'TR'].includes(code),
    rentersRights: gb,                            // England: Renters' Rights Act deadlines
    compliance: gb,                               // gas safety · electrical check · deposit protection
    mtd: gb,                                      // Making Tax Digital quarterly records
    lateInterest: gb,                             // statutory interest on late business invoices
    missedCallText: true,
    replyLanguage: pk ? 'English · Urdu · Roman Urdu' : south ? 'English · local language' : 'the client’s own language',
  };
}
/** Short, friendly list for the "what you get" popup. */
export function featureList(code) {
  const f = features(code), L = [];
  L.push(['💬', 'WhatsApp enquiries become leads', `Replies in ${f.replyLanguage}`]);
  L.push(['⏱️', 'Speed-to-lead alarm', 'Nobody waits more than 5 minutes']);
  L.push(['💸', 'Lost money report', 'See the enquiries nobody followed up']);
  L.push(['📞', 'Missed call → WhatsApp', 'Instant reply when you can’t pick up']);
  if (f.groupListings) L.push(['🏘️', 'WhatsApp group posts → stock', 'Dealer posts become listings, matched to buyers']);
  if (f.installments) L.push(['🧾', 'Tokens & installments', 'Due dates and reminders']);
  if (f.rentersRights) L.push(['⚖️', 'Renters’ Rights deadline guard', 'Pet requests, rent rises, notices']);
  if (f.compliance) L.push(['🛡️', 'Safety certificates', 'Gas, electrical, deposit protection']);
  if (f.mtd) L.push(['📊', 'Making Tax Digital records', 'Quarterly summary for your accountant']);
  L.push(['🔁', 'Rebooking & money chasers', 'Clients come back, invoices get paid']);
  L.push([' ', `Payments: ${f.methods.slice(0, 4).join(', ')}`, `Leads from ${f.portals.slice(0, 4).join(', ')}`]);
  return L;
}
