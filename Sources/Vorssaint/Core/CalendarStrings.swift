// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct CalendarFeatureStrings {
    let title: String
    let panelCaption: String
    let calendarsListTitle: String
    let hideCalendarHint: String
    let hubDescription: String
    let permission: String
    let allow: String
    let denied: String
    let settings: String
    let requestFailed: String
    let empty: String
    let today: String
    let allDay: String
    let untitled: String
    let openCalendar: String
    let previousMonth: String
    let nextMonth: String
}

extension FeatureStrings {
    static func calendar(_ language: AppLanguage) -> CalendarFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension CalendarFeatureStrings {
    static let enUS = CalendarFeatureStrings(title: "Calendar", panelCaption: "Browse your calendar and upcoming events", calendarsListTitle: "Calendars", hideCalendarHint: "Calendars hidden here are removed from the grid and agenda, not from Calendar itself.", hubDescription: "Browse a month view and your upcoming appointments from the menu bar panel.", permission: "Read your calendars to show upcoming appointments. Events stay on this Mac.", allow: "Allow Calendar Access", denied: "Allow calendar access in System Settings to see your appointments.", settings: "Open System Settings", requestFailed: "Could not request calendar access. Please try again.", empty: "No upcoming appointments", today: "Today", allDay: "All day", untitled: "Untitled event", openCalendar: "Open Calendar", previousMonth: "Previous month", nextMonth: "Next month")
    static let ptBR = CalendarFeatureStrings(title: "Calendário", panelCaption: "Veja seu calendário e próximos compromissos", calendarsListTitle: "Calendários", hideCalendarHint: "Calendários ocultados aqui são removidos da grade e da agenda, não do app Calendário em si.", hubDescription: "Veja uma visão mensal e seus próximos compromissos no painel da barra de menus.", permission: "Leia seus calendários para mostrar os próximos compromissos. Os eventos ficam neste Mac.", allow: "Permitir acesso ao calendário", denied: "Permita o acesso ao calendário nos Ajustes do Sistema para ver seus compromissos.", settings: "Abrir Ajustes do Sistema", requestFailed: "Não foi possível pedir acesso ao calendário. Tente novamente.", empty: "Nenhum compromisso por enquanto", today: "Hoje", allDay: "Dia inteiro", untitled: "Evento sem título", openCalendar: "Abrir calendário", previousMonth: "Mês anterior", nextMonth: "Próximo mês")
    static let tr = CalendarFeatureStrings(title: "Takvim", panelCaption: "Takviminizi ve yaklaşan randevularınızı görüntüleyin", calendarsListTitle: "Takvimler", hideCalendarHint: "Burada gizlenen takvimler, ızgara ve gündemden kaldırılır; Takvim uygulamasından kaldırılmaz.", hubDescription: "Menü çubuğu panelinden aylık görünümü ve yaklaşan randevularınızı görüntüleyin.", permission: "Yaklaşan randevuları göstermek için takvimlerinizi okur. Etkinlikler bu Mac’te kalır.", allow: "Takvim Erişimine İzin Ver", denied: "Randevularınızı görmek için Sistem Ayarları’nda takvim erişimine izin verin.", settings: "Sistem Ayarları’nı Aç", requestFailed: "Takvim erişimi istenemedi. Tekrar deneyin.", empty: "Yaklaşan randevu yok", today: "Bugün", allDay: "Tüm gün", untitled: "Başlıksız etkinlik", openCalendar: "Takvimi Aç", previousMonth: "Önceki ay", nextMonth: "Sonraki ay")
    static let ru = CalendarFeatureStrings(title: "Календарь", panelCaption: "Просмотр календаря и предстоящих встреч", calendarsListTitle: "Календари", hideCalendarHint: "Скрытые здесь календари удаляются из сетки и повестки дня, но не из самого приложения «Календарь».", hubDescription: "Просмотр месяца и предстоящих встреч в панели строки меню.", permission: "Чтение календарей для показа предстоящих встреч. События остаются на этом Mac.", allow: "Разрешить доступ к календарю", denied: "Разрешите доступ к календарю в Системных настройках, чтобы видеть встречи.", settings: "Открыть Системные настройки", requestFailed: "Не удалось запросить доступ к календарю. Повторите попытку.", empty: "Предстоящих встреч нет", today: "Сегодня", allDay: "Весь день", untitled: "Событие без названия", openCalendar: "Открыть Календарь", previousMonth: "Предыдущий месяц", nextMonth: "Следующий месяц")
    static let es = CalendarFeatureStrings(title: "Calendario", panelCaption: "Consulta tu calendario y tus próximas citas", calendarsListTitle: "Calendarios", hideCalendarHint: "Los calendarios ocultos aquí se eliminan de la cuadrícula y la agenda, no de la app Calendario.", hubDescription: "Consulta una vista mensual y tus próximas citas desde el panel de la barra de menús.", permission: "Lee tus calendarios para mostrar las próximas citas. Los eventos se quedan en este Mac.", allow: "Permitir acceso al calendario", denied: "Permite el acceso al calendario en Ajustes del Sistema para ver tus citas.", settings: "Abrir Ajustes del Sistema", requestFailed: "No se pudo solicitar acceso al calendario. Inténtalo de nuevo.", empty: "No hay próximas citas", today: "Hoy", allDay: "Todo el día", untitled: "Evento sin título", openCalendar: "Abrir Calendario", previousMonth: "Mes anterior", nextMonth: "Mes siguiente")
    static let de = CalendarFeatureStrings(title: "Kalender", panelCaption: "Kalender und anstehende Termine durchsehen", calendarsListTitle: "Kalender", hideCalendarHint: "Hier ausgeblendete Kalender werden aus dem Raster und der Agenda entfernt, nicht aus Kalender selbst.", hubDescription: "Monatsansicht und anstehende Termine im Menüleisten-Panel durchsehen.", permission: "Liest deine Kalender, um kommende Termine anzuzeigen. Die Ereignisse bleiben auf diesem Mac.", allow: "Kalenderzugriff erlauben", denied: "Erlaube den Kalenderzugriff in den Systemeinstellungen, um deine Termine zu sehen.", settings: "Systemeinstellungen öffnen", requestFailed: "Der Kalenderzugriff konnte nicht angefordert werden. Versuche es erneut.", empty: "Keine anstehenden Termine", today: "Heute", allDay: "Ganztägig", untitled: "Ereignis ohne Titel", openCalendar: "Kalender öffnen", previousMonth: "Vorheriger Monat", nextMonth: "Nächster Monat")
    static let fr = CalendarFeatureStrings(title: "Calendrier", panelCaption: "Consultez votre calendrier et vos prochains rendez-vous", calendarsListTitle: "Calendriers", hideCalendarHint: "Les calendriers masqués ici sont retirés de la grille et de l’agenda, pas de l’app Calendrier elle-même.", hubDescription: "Consultez une vue mensuelle et vos prochains rendez-vous depuis le panneau de la barre des menus.", permission: "Lit vos calendriers pour afficher les prochains rendez-vous. Les événements restent sur ce Mac.", allow: "Autoriser l’accès au calendrier", denied: "Autorisez l’accès au calendrier dans les Réglages Système pour voir vos rendez-vous.", settings: "Ouvrir les Réglages Système", requestFailed: "Impossible de demander l’accès au calendrier. Réessayez.", empty: "Aucun rendez-vous à venir", today: "Aujourd’hui", allDay: "Toute la journée", untitled: "Événement sans titre", openCalendar: "Ouvrir Calendrier", previousMonth: "Mois précédent", nextMonth: "Mois suivant")
    static let it = CalendarFeatureStrings(title: "Calendario", panelCaption: "Consulta il calendario e i prossimi appuntamenti", calendarsListTitle: "Calendari", hideCalendarHint: "I calendari nascosti qui vengono rimossi dalla griglia e dall’agenda, non dall’app Calendario stessa.", hubDescription: "Consulta una vista mensile e i tuoi prossimi appuntamenti dal pannello della barra dei menu.", permission: "Legge i calendari per mostrare i prossimi appuntamenti. Gli eventi restano su questo Mac.", allow: "Consenti accesso al calendario", denied: "Consenti l’accesso al calendario in Impostazioni di Sistema per vedere gli appuntamenti.", settings: "Apri Impostazioni di Sistema", requestFailed: "Impossibile richiedere l’accesso al calendario. Riprova.", empty: "Nessun appuntamento in programma", today: "Oggi", allDay: "Tutto il giorno", untitled: "Evento senza titolo", openCalendar: "Apri Calendario", previousMonth: "Mese precedente", nextMonth: "Mese successivo")
    static let ja = CalendarFeatureStrings(title: "カレンダー", panelCaption: "カレンダーと今後の予定を確認", calendarsListTitle: "カレンダー", hideCalendarHint: "ここで非表示にしたカレンダーは、グリッドとアジェンダから外れるだけで、カレンダーApp自体からは削除されません。", hubDescription: "メニューバーパネルから月表示と今後の予定を確認できます。", permission: "カレンダーを読み取り、今後の予定を表示します。予定の情報はこのMacに保持されます。", allow: "カレンダーへのアクセスを許可", denied: "予定を表示するには、システム設定でカレンダーへのアクセスを許可してください。", settings: "システム設定を開く", requestFailed: "カレンダーへのアクセスを要求できませんでした。もう一度お試しください。", empty: "今後の予定はありません", today: "今日", allDay: "終日", untitled: "名称未設定の予定", openCalendar: "カレンダーを開く", previousMonth: "前の月", nextMonth: "次の月")
    static let ko = CalendarFeatureStrings(title: "캘린더", panelCaption: "캘린더와 다가오는 일정 보기", calendarsListTitle: "캘린더", hideCalendarHint: "여기서 숨긴 캘린더는 그리드와 일정 목록에서만 제외되며, 캘린더 앱 자체에서 삭제되지는 않습니다.", hubDescription: "메뉴 막대 패널에서 월별 보기와 다가오는 일정을 확인하세요.", permission: "다가오는 일정을 표시하기 위해 캘린더를 읽습니다. 일정은 이 Mac에만 보관됩니다.", allow: "캘린더 접근 허용", denied: "일정을 보려면 시스템 설정에서 캘린더 접근을 허용하세요.", settings: "시스템 설정 열기", requestFailed: "캘린더 접근을 요청할 수 없습니다. 다시 시도하세요.", empty: "예정된 일정 없음", today: "오늘", allDay: "하루 종일", untitled: "제목 없는 일정", openCalendar: "캘린더 열기", previousMonth: "이전 달", nextMonth: "다음 달")
    static let zhHans = CalendarFeatureStrings(title: "日历", panelCaption: "浏览日历和即将开始的日程", calendarsListTitle: "日历", hideCalendarHint: "在此隐藏的日历只会从网格和日程列表中移除，不会影响日历App本身。", hubDescription: "在菜单栏面板中浏览月视图和即将开始的日程。", permission: "读取日历以显示即将开始的日程。日程信息仅保留在此 Mac 上。", allow: "允许访问日历", denied: "请在系统设置中允许访问日历，以查看日程。", settings: "打开系统设置", requestFailed: "无法请求日历访问权限，请重试。", empty: "暂无即将开始的日程", today: "今天", allDay: "全天", untitled: "无标题日程", openCalendar: "打开日历", previousMonth: "上个月", nextMonth: "下个月")
    static let zhTW = CalendarFeatureStrings(title: "行事曆", panelCaption: "瀏覽行事曆與即將到來的行程", calendarsListTitle: "行事曆", hideCalendarHint: "在此隱藏的行事曆只會從方格與行程列表中移除，不會影響行事曆App本身。", hubDescription: "在選單列面板中瀏覽月檢視與即將到來的行程。", permission: "讀取行事曆以顯示即將到來的行程。行程資訊僅保留在這部 Mac 上。", allow: "允許取用行事曆", denied: "請在系統設定中允許取用行事曆，以查看行程。", settings: "打開系統設定", requestFailed: "無法要求行事曆取用權限，請再試一次。", empty: "沒有即將到來的行程", today: "今天", allDay: "整天", untitled: "未命名行程", openCalendar: "打開行事曆", previousMonth: "上個月", nextMonth: "下個月")
    static let zhHK = CalendarFeatureStrings(title: "日曆", panelCaption: "瀏覽日曆與即將到來的行程", calendarsListTitle: "日曆", hideCalendarHint: "在此隱藏的日曆只會從方格與行程列表中移除，不會影響日曆App本身。", hubDescription: "在選單列面板中瀏覽月檢視與即將到來的行程。", permission: "讀取日曆以顯示即將到來的行程。行程資料只保留在此 Mac 上。", allow: "允許取用日曆", denied: "請在系統設定中允許取用日曆，以查看行程。", settings: "開啟系統設定", requestFailed: "無法要求日曆取用權限，請重試。", empty: "沒有即將到來的行程", today: "今天", allDay: "全天", untitled: "未命名行程", openCalendar: "開啟日曆", previousMonth: "上個月", nextMonth: "下個月")
}
