// Paycheck Pal

import SwiftUI

// ==========================
// MARK: - Model
// ==========================
struct WorkRecord: Identifiable, Codable {
    var id: UUID = UUID()
    var date: Date // the day user worked (use start date's day)
    var startTime: Date
    var endTime: Date
    var totalSeconds: Int // end - start in seconds
    var hoursAndMinutesDisplay: String
    var halfHourDecimal: Double
    var salary: Double
    var hourly: Double
    var modifiedHourly: Bool
    var description: String
    var usesCustomPayWindow: Bool = false
    var customPayStartMinutes: Int = 0
    var customPayEndMinutes: Int = 0
}

// ==========================
// MARK: - Persistence Manager (JSON File)
// ==========================
final class DataManager: ObservableObject {
    static let shared = DataManager()
    @Published var records: [WorkRecord] = []
    
    private let filename = "work_records.json"
    
    private init() {
        load()
    }
    
    private var fileURL: URL? {
        do {
            let fm = FileManager.default
            let doc = try fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            return doc.appendingPathComponent(filename)
        } catch {
            return nil
        }
    }
    
    func save() {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: url, options: [.atomicWrite])
        } catch {
            print("Failed to save records: \(error)")
        }
    }
    
    func load() {
        guard let url = fileURL else { return }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([WorkRecord].self, from: data)
            self.records = decoded
        } catch {
            // ignore — no file yet or decode failed
            self.records = []
        }
    }
    
    func add(_ record: WorkRecord) {
        records.insert(record, at: 0)
        save()
    }
    
    func remove(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        save()
    }
    
    func replace(_ record: WorkRecord) {
        if let idx = records.firstIndex(where: { $0.id == record.id }) {
            records[idx] = record
            save()
        }
    }

    // Recompute a single record using either its custom pay window or the global one,
    // then update totals and salary with the provided hourly.
    func recompute(_ rec: WorkRecord,
                   hourly: Double,
                   globalEnabled: Bool,
                   globalStart: Int,
                   globalEnd: Int) -> WorkRecord {
        let effectiveEnabled = rec.usesCustomPayWindow ? true : globalEnabled
        let effectiveStartMin = rec.usesCustomPayWindow ? rec.customPayStartMinutes : globalStart
        let effectiveEndMin = rec.usesCustomPayWindow ? rec.customPayEndMinutes : globalEnd
        
        let interval = paidIntervalSeconds(start: rec.startTime,
                                           end: rec.endTime,
                                           enabled: effectiveEnabled,
                                           startMinutes: effectiveStartMin,
                                           endMinutes: effectiveEndMin)
        let newHalf = halfHourRoundedDecimal(from: interval)
        
        var updated = rec
        updated.totalSeconds = interval
        updated.hoursAndMinutesDisplay = formatHoursMinutes(from: interval)
        updated.halfHourDecimal = newHalf
        updated.salary = newHalf * hourly
        updated.hourly = hourly
        return updated
    }
    
    // Apply wage + pay-window recomputation to all records; returns number of affected records.
    func applyToAll(hourly: Double,
                    applyToModifiedHourly: Bool,
                    globalEnabled: Bool,
                    globalStart: Int,
                    globalEnd: Int) -> Int {
        var count = 0
        for idx in records.indices {
            let rec = records[idx]
            if applyToModifiedHourly || !rec.modifiedHourly {
                records[idx] = recompute(rec,
                                         hourly: hourly,
                                         globalEnabled: globalEnabled,
                                         globalStart: globalStart,
                                         globalEnd: globalEnd)
                count += 1
            }
        }
        save()
        return count
    }
    
    // Apply wage + pay-window recomputation to a specific (year, month); returns number of affected records.
    func applyToMonth(year: Int,
                      month: Int,
                      hourly: Double,
                      applyToModifiedHourly: Bool,
                      globalEnabled: Bool,
                      globalStart: Int,
                      globalEnd: Int) -> Int {
        var count = 0
        let cal = Calendar.current
        for idx in records.indices {
            let rec = records[idx]
            let y = cal.component(.year, from: rec.date)
            let m = cal.component(.month, from: rec.date)
            if y == year && m == month {
                if applyToModifiedHourly || !rec.modifiedHourly {
                    records[idx] = recompute(rec,
                                             hourly: hourly,
                                             globalEnabled: globalEnabled,
                                             globalStart: globalStart,
                                             globalEnd: globalEnd)
                    count += 1
                }
            }
        }
        save()
        return count
    }
}


// ==========================
// MARK: - Helpers
// ==========================
extension Date {
    func startOfDay() -> Date {
        Calendar.current.startOfDay(for: self)
    }
}

func formatHoursMinutes(from totalSeconds: Int) -> String {
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    return "\(hours) 小時 \(minutes) 分鐘"
}

func halfHourRoundedDecimal(from totalSeconds: Int) -> Double {
    let hoursDecimal = Double(totalSeconds) / 3600.0
    let steps = floor(hoursDecimal / 0.5) // floor to nearest 0.5
    return steps * 0.5
}

// Pay Window Helpers
func minutesSinceMidnight(_ date: Date) -> Int {
    let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
}

func dateAtMinutes(base: Date, minutes: Int) -> Date {
    Calendar.current.date(byAdding: .minute, value: minutes, to: base.startOfDay())!
}

func hmString(_ minutes: Int) -> String {
    let h = minutes / 60
    let m = minutes % 60
    return String(format: "%02d:%02d", h, m)
}

/// Compute the paid interval in seconds by intersecting [start, end] with the pay window.
/// If `enabled` is false, returns the full interval between start and end.
/// If endMinutes <= startMinutes, the pay window is treated as spanning across midnight into the next day.
func paidIntervalSeconds(start: Date, end: Date, enabled: Bool, startMinutes: Int, endMinutes: Int) -> Int {
    let full = Int(end.timeIntervalSince(start))
    if !enabled { return max(0, full) }
    if end <= start { return 0 }

    let base = start.startOfDay()
    let windowStart = dateAtMinutes(base: base, minutes: startMinutes)
    var windowEnd = dateAtMinutes(base: base, minutes: endMinutes)
    // If the window end is not after start (e.g., 22:00 -> 06:00), roll to next day
    if windowEnd <= windowStart {
        windowEnd = Calendar.current.date(byAdding: .day, value: 1, to: windowEnd)!
    }

    let effectiveStart = max(start, windowStart)
    let effectiveEnd   = min(end, windowEnd)
    let interval = effectiveEnd.timeIntervalSince(effectiveStart)
    return max(0, Int(interval))
}


// Cached DateFormatters (avoid repeated allocations)
enum DF {
    static let yearMonth: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM"
        return f
    }()
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd (E)"
        return f
    }()
    static let hm12: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f
    }()
    static let dateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd (E) HH:mm"
        return f
    }()
}


// Date/Calendar Helpers (unified)
func year(_ d: Date) -> Int { Calendar.current.component(.year, from: d) }
func month(_ d: Date) -> Int { Calendar.current.component(.month, from: d) }

func addMonths(_ d: Date, offset: Int) -> Date {
    Calendar.current.date(byAdding: .month, value: offset, to: d)!
}

func formatYearMonth(_ d: Date) -> String {
    DF.yearMonth.string(from: d)
}

func formatShortDate(_ d: Date) -> String {
    DF.shortDate.string(from: d)
}

func formatTimeHM(_ d: Date) -> String {
    DF.hm12.string(from: d)
}

func offsetYearMonthKey(offset: Int) -> String {
    formatYearMonth(addMonths(Date(), offset: offset))
}

// ==========================
// MARK: - App Storage Keys
// ==========================
@propertyWrapper
struct AppStoredDouble {
    let key: String
    let defaultValue: Double
    var wrappedValue: Double {
        get { UserDefaults.standard.double(forKey: key) == 0 ? defaultValue : UserDefaults.standard.double(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// ==========================
// MARK: - Main App
// ==========================
@main
struct PaycheckPalApp: App {
    @AppStorage("wagePerHour") var wagePerHour: Double = 0.0
    @StateObject var dataManager = DataManager.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(dataManager)
                .onAppear {
                    // nothing special
                }
        }
    }
}

// ==========================
// MARK: - Root View
// ==========================
struct RootView: View {
    @AppStorage("wagePerHour") var wagePerHour: Double = 0.0
    @EnvironmentObject var dataManager: DataManager
    @State private var showingSettings = false
    @State private var monthOffset = 0 // for monthLabel func, 0 = current month
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Divider()
                Divider()
                HStack {
                    VStack(alignment: .leading) {
                        HStack(spacing: 0) {
                            Text("時薪：")
                                .font(.headline)
                            GradientGlowText(text:"\(Int(wagePerHour)) 元")
                        }
                        Text("半小時計算規則：不足0.5小時直接捨棄")
                            .font(.caption)
                    }
                    Spacer()
                    Button("設定") { showingSettings = true }
                }
                .padding(.horizontal)
                Divider()
                ClockPunchView()
                    .padding(.horizontal)
                Divider()
                SummaryView(monthOffset: $monthOffset)
                    .padding(.horizontal)
                Divider()
                RecordsListView(monthOffset: monthOffset)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button(action: { showLog() }) {
                        GradientGlowText(text: "Paycheck Pal")
                            .font(.title)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("PaycheckPalTitleButton")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingSettings) {
                WageSettingsView()
            }
            .onAppear {
                // first launch: if wage == 0 prompt settings sheet
                if wagePerHour == 0 { showingSettings = true }
            }
        }
    }
    
    func showLog () {
        let dateFormatter = DF.dateTime
        print(dataManager.records)
        print("\n\n------------\n\n")
        for record in dataManager.records {
            let dateStr = dateFormatter.string(from: record.date)
            let startStr = dateFormatter.string(from: record.startTime)
            let endStr = dateFormatter.string(from: record.endTime)
            let customLines = record.usesCustomPayWindow
            ? "CustomPayWindowStart: \(hmString(record.customPayStartMinutes))\nCustomPayWindowEnd: \(hmString(record.customPayEndMinutes))\n"
            : ""
            print("""
                \n--------------------------
                Date: \(dateStr)
                Start: \(startStr)
                End: \(endStr)
                Hours: \(record.hoursAndMinutesDisplay)
                HalfHourDecimal: \(String(format: "%.1f", record.halfHourDecimal))
                Salary: \(Int(record.salary)) 元
                Hourly: \(Int(record.hourly)) 元
                ModifiedHourly: \(record.modifiedHourly)
                Description: \(record.description)
                CustomPayWindow: \(record.usesCustomPayWindow)
                \(customLines)
                """)
        }
    }
}


// ==========================
// MARK: - Subtle Gradient Stroke + Glow
// ==========================
struct GradientGlowText: View {
    var text: String
    var period: Double = 6 // seconds per full color cycle
    var font: Font? = nil
    var weight: Font.Weight? = nil
    @Environment(\.font) private var envFont

    var body: some View {
        TimelineView(.animation) { context in
            let usedFont = font ?? envFont ?? .headline
            let base: Text = {
                var t = Text(text).font(usedFont)
                if let weight { t = t.fontWeight(weight) }
                return t
            }()

            let gradient = LinearGradient(
                colors: [Color.cyan, Color.blue, Color.purple],
                startPoint: .leading,
                endPoint: .trailing
            )

            // Global, time-based phase so every instance stays in sync
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: period)) / period
            let angle = Angle(degrees: -phase * 360)

            base
                .foregroundColor(.clear)
                .overlay(
                    gradient
                        .mask(base)
                        .hueRotation(angle)
                )
        }
    }
}


// ==========================
// MARK: - Wage Settings
// ==========================
struct WageSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("wagePerHour") var wagePerHour: Double = 0.0
    @AppStorage("payWindowEnabled") var payWindowEnabled: Bool = false
    @AppStorage("payStartMinutes") var payStartMinutes: Int = 9 * 60
    @AppStorage("payEndMinutes") var payEndMinutes: Int = 18 * 60
    @State private var tempWage: String = ""
    @EnvironmentObject var dataManager: DataManager
    @State private var applyToModifiedHourly: Bool = false
    @State private var appliedRecordCounter: Int = 0
    @State private var showAppliedAlert:Bool = false
    @State private var tempPayStart: Date = Date()
    @State private var tempPayEnd: Date = Date()
    
    
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("設定時薪（每小時）")) {
                    TextField("時薪（數字）", text: $tempWage)
                        .keyboardType(.decimalPad)
                }
                Section {
                    Button("儲存") {
                        if let v = Double(tempWage) {
                            wagePerHour = v
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                    Button("取消") { presentationMode.wrappedValue.dismiss() }
                }
                // Pay Window Settings Section
                Section(header: Text("支薪時段限制")) {
                    Toggle("啟用支薪時段限制", isOn: $payWindowEnabled)
                    if payWindowEnabled {
                        DatePicker("開始支薪時間", selection: $tempPayStart, displayedComponents: .hourAndMinute)
                        DatePicker("停止支薪時間", selection: $tempPayEnd, displayedComponents: .hourAndMinute)
                            .onChange(of: tempPayStart) { _, newValue in
                                payStartMinutes = minutesSinceMidnight(newValue)
                            }
                            .onChange(of: tempPayEnd) { _, newValue in
                                payEndMinutes = minutesSinceMidnight(newValue)
                            }
                        Text("目前有效支薪區間：\(hmString(payStartMinutes)) - \(hmString(payEndMinutes))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                if wagePerHour != 0 {
                    Toggle("同步應用到手動修改時薪", isOn: $applyToModifiedHourly)
                    Button("應用到本月紀錄") {
                        if let v = Double(tempWage) {
                            wagePerHour = v
                        }
                        appliedRecordCounter = 0
                        let now = Date()
                        let cal = Calendar.current
                        let y = cal.component(.year, from: now)
                        let m = cal.component(.month, from: now)
                        appliedRecordCounter = dataManager.applyToMonth(year: y,
                                                                        month: m,
                                                                        hourly: wagePerHour,
                                                                        applyToModifiedHourly: applyToModifiedHourly,
                                                                        globalEnabled: payWindowEnabled,
                                                                        globalStart: payStartMinutes,
                                                                        globalEnd: payEndMinutes)
                        showAppliedAlert = true
                    }
                    Button("應用到全部紀錄") {
                        if let v = Double(tempWage) {
                            wagePerHour = v
                        }
                        appliedRecordCounter = dataManager.applyToAll(hourly: wagePerHour,
                                                                      applyToModifiedHourly: applyToModifiedHourly,
                                                                      globalEnabled: payWindowEnabled,
                                                                      globalStart: payStartMinutes,
                                                                      globalEnd: payEndMinutes)
                        showAppliedAlert = true
                    }
                }
            }
            .navigationTitle("時薪設定")
            .onAppear {
                tempWage = wagePerHour == 0 ? "" : String(format: "%.0f", wagePerHour)
                let base = Date().startOfDay()
                tempPayStart = dateAtMinutes(base: base, minutes: payStartMinutes)
                tempPayEnd = dateAtMinutes(base: base, minutes: payEndMinutes)
            }
            .alert(isPresented: $showAppliedAlert) {
                Alert(
                    title: Text("完成"),
                    message: Text("已應用到 \(appliedRecordCounter) 筆紀錄"),
                    dismissButton: .default(Text("確定")) {
                        showAppliedAlert = false
                        presentationMode.wrappedValue.dismiss()
                    }
                )
            }
        }
    }
    
    func yearMonth(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM"
        return f.string(from: d)
    }
    
}

// ==========================
// MARK: - Clock Punch View
// ==========================
struct ClockPunchView: View {
    @State private var startTime: Date? = nil
    @State private var endTime: Date? = nil
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("wagePerHour") var wagePerHour: Double = 0
    @AppStorage("payWindowEnabled") var payWindowEnabled: Bool = false
    @AppStorage("payStartMinutes") var payStartMinutes: Int = 9 * 60
    @AppStorage("payEndMinutes") var payEndMinutes: Int = 18 * 60
    @State private var toastText: String? = nil
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("上班：\(startTime != nil ? timeString(startTime!) : "--:--")")
                    Text("下班：\(endTime != nil ? timeString(endTime!) : "--:--")")
                }
                Spacer()
            }
            HStack {
                if payWindowEnabled {
                    Text("支薪時段：\(hmString(payStartMinutes)) - \(hmString(payEndMinutes))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("支薪時段：關閉")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 20) {
                Button(action: punchIn) {
                    Text("上班")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).stroke())
                }
                Button(action: punchOut) {
                    Text("下班")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 12).stroke())
                }
            }
            if let toast = toastText {
                Text(toast)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    func timeString(_ d: Date) -> String {
        DF.hm12.string(from: d)
    }
    
    func punchIn() {
        if startTime != nil {
            toastText = "還在上班喔，先按下班再上班"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { toastText = nil }
            return
        }
        startTime = Date()
        // reset endTime so user can punch out later
        endTime = nil
        toastText = "上班打卡：\(timeString(startTime!))"
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { toastText = nil }
    }
    
    func punchOut() {
        guard let start = startTime else {
            toastText = "還沒按上班喔，先按上班再下班"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { toastText = nil }
            return
        }
        let end = Date()
        endTime = end

        let interval = paidIntervalSeconds(start: start, end: end, enabled: payWindowEnabled, startMinutes: payStartMinutes, endMinutes: payEndMinutes)
        if interval <= 0 {
            startTime = nil
            endTime = nil
            toastText = "無效紀錄"
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { toastText = nil }
            return
        }

        let hAndM = formatHoursMinutes(from: interval)
        let half = halfHourRoundedDecimal(from: interval)
        let salary = half * wagePerHour

        let record = WorkRecord(date: start.startOfDay(), startTime: start, endTime: end, totalSeconds: interval, hoursAndMinutesDisplay: hAndM, halfHourDecimal: half, salary: salary, hourly: wagePerHour, modifiedHourly: false, description: "")

        dataManager.add(record)

        // reset punch state for next time
        startTime = nil
        endTime = nil

        toastText = "已記錄：\(hAndM)，半小時制：\(String(format: "%.1f", half))小時，當日薪資：\(Int(salary)) 元"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { toastText = nil }
    }
}

// ==========================
// MARK: - Records List
// ==========================
struct RecordsListView: View {
    @EnvironmentObject var dataManager: DataManager
    @State private var showingEdit: WorkRecord? = nil
    let monthOffset: Int
    
    var body: some View {
        let target = offsetYearMonthKey(offset: monthOffset)
        List {
            Section(header: Text("紀錄")) {
                ForEach(dataManager.records) { rec in
                    if formatYearMonth(rec.date) == target {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(formatShortDate(rec.date))
                                    .font(.headline)
                                Spacer()
                                GradientGlowText(text: "\(Int(rec.salary)) 元")
                            }
                            HStack {
                                Text("上班：\(formatTimeHM(rec.startTime))")
                                Text("下班：\(formatTimeHM(rec.endTime))")
                            }
                            HStack {
                                let formmatedHalfHour = String(format: "%.1f 小時", rec.halfHourDecimal)
                                Text(rec.hoursAndMinutesDisplay)
                                Text("(\(formmatedHalfHour))")
                                Spacer()
                                if rec.modifiedHourly {
                                    Text("*")
                                }
                                if rec.usesCustomPayWindow {
                                    Text("^")
                                }
                                Text("時薪：\(Int(rec.hourly))元")
                                    .font(.subheadline)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { showingEdit = rec }
                    }
                }
                .onDelete(perform: dataManager.remove)
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $showingEdit) { record in
            EditRecordView(record: record)
        }
    }
}

// ==========================
// MARK: - Edit Record
// ==========================
struct EditRecordView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("payWindowEnabled") var payWindowEnabled: Bool = false
    @AppStorage("payStartMinutes") var payStartMinutes: Int = 9 * 60
    @AppStorage("payEndMinutes") var payEndMinutes: Int = 18 * 60
    @State var record: WorkRecord
    @State private var tempHourly: String = ""
    @State private var originalHourly: String = ""
    @State private var description: String = ""
    @State private var tempStartTime: Date = Date()
    @State private var tempEndTime: Date = Date()
    @State private var useCustomPayWindow: Bool = false
    @State private var tempCustomStart: Date = Date()
    @State private var tempCustomEnd: Date = Date()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("時間")) {
                    DatePicker("上班", selection: $tempStartTime, displayedComponents: [.hourAndMinute, .date])
                    DatePicker("下班", selection: $tempEndTime, displayedComponents: [.hourAndMinute, .date])
                }

                Section(header: Text("支薪時段（此紀錄）")) {
                    Toggle("此紀錄使用自訂支薪時段", isOn: $useCustomPayWindow)
                    if useCustomPayWindow {
                        DatePicker("開始支薪時間", selection: $tempCustomStart, displayedComponents: .hourAndMinute)
                        DatePicker("停止支薪時間", selection: $tempCustomEnd, displayedComponents: .hourAndMinute)
                        Text("有效支薪區間：\(hmString(minutesSinceMidnight(tempCustomStart))) - \(hmString(minutesSinceMidnight(tempCustomEnd)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("使用全域支薪設定")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                var isValidTime: Bool{
                    Int(tempEndTime.timeIntervalSince(tempStartTime)) > 0
                }

                Section(header: Text("時薪")) {
                    TextField("時薪（數字）", text: $tempHourly)
                        .keyboardType(.decimalPad)
                }

                Section(header: Text("備註")) {
                    TextField("", text: $description)
                        .submitLabel(.done)
                }

                Section {
                    if isValidTime {
                        Button("更新") {
                            if tempHourly != originalHourly {
                                record.hourly = Double(tempHourly) ?? record.hourly
                                record.modifiedHourly = true
                            }
                            record.startTime = tempStartTime
                            record.endTime = tempEndTime

                            // Persist per-record pay window override
                            record.usesCustomPayWindow = useCustomPayWindow
                            if useCustomPayWindow {
                                record.customPayStartMinutes = minutesSinceMidnight(tempCustomStart)
                                record.customPayEndMinutes = minutesSinceMidnight(tempCustomEnd)
                            }

                            // Choose effective window (record override > global)
                            let effectiveEnabled = useCustomPayWindow ? true : payWindowEnabled
                            let effectiveStartMin = useCustomPayWindow ? record.customPayStartMinutes : payStartMinutes
                            let effectiveEndMin = useCustomPayWindow ? record.customPayEndMinutes : payEndMinutes

                            let interval = paidIntervalSeconds(start: record.startTime, end: record.endTime, enabled: effectiveEnabled, startMinutes: effectiveStartMin, endMinutes: effectiveEndMin)
                            record.totalSeconds = interval
                            record.hoursAndMinutesDisplay = formatHoursMinutes(from: record.totalSeconds)
                            record.halfHourDecimal = halfHourRoundedDecimal(from: record.totalSeconds)
                            record.salary = record.halfHourDecimal * record.hourly
                            record.date = record.startTime.startOfDay()
                            record.description = description
                            dataManager.replace(record)
                            presentationMode.wrappedValue.dismiss()
                        }
                    } else{
                        Text ("上班時間必須早於下班時間")
                            .foregroundColor(.red)
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(5)
                            .font(.system(size: 500))
                            .minimumScaleFactor(0.01)
                            .lineLimit(1)
                    }

                    Button("取消") { presentationMode.wrappedValue.dismiss() }

                }

                Section {
                    if record.modifiedHourly {
                        Button("重置時薪編輯標記") {
                            record.modifiedHourly = false
                            dataManager.replace(record)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }

            }
            .navigationTitle("編輯紀錄")
            .onAppear{
                tempHourly = String(format: "%.0f", record.hourly)
                originalHourly = tempHourly
                description = record.description
                tempStartTime = record.startTime
                tempEndTime = record.endTime
                useCustomPayWindow = record.usesCustomPayWindow
                let base = record.startTime.startOfDay()
                if record.usesCustomPayWindow {
                    tempCustomStart = dateAtMinutes(base: base, minutes: record.customPayStartMinutes)
                    tempCustomEnd = dateAtMinutes(base: base, minutes: record.customPayEndMinutes)
                } else {
                    tempCustomStart = dateAtMinutes(base: base, minutes: payStartMinutes)
                    tempCustomEnd = dateAtMinutes(base: base, minutes: payEndMinutes)
                }
            }
        }
    }
}

// ==========================
// MARK: - Summary View
// ==========================
struct SummaryView: View {
    @EnvironmentObject var dataManager: DataManager
    @AppStorage("wagePerHour") var wagePerHour: Double = 0
    @Binding var monthOffset: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Stepper("年月份：\(monthLabel())", value: $monthOffset, in: -12...12)
            }
            let filtered = recordsForMonth(offset: monthOffset)
            let totalSeconds = filtered.map { $0.totalSeconds }.reduce(0, +)
            let totalHalf = filtered.map { $0.halfHourDecimal }.reduce(0, +)
            let totalSalary = filtered.map { $0.salary }.reduce(0, +)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("總時數（小時:分鐘）: \(formatHoursMinutes(from: totalSeconds))")
                    Text(String(format: "總時數  （0.5進位) : %.1f 小時", totalHalf))
                    HStack(spacing: 0) {
                        Text("當月薪資：")
                        GradientGlowText(text:"\(Int(totalSalary)) 元")
                        Spacer()
                        if monthOffset != 0 {
                            Button("本月") {
                                monthOffset = 0
                            }
                        }
                    }
                }
                Spacer()
            }
        }
    }
    
    func monthLabel() -> String {
        let target = addMonths(Date(), offset: monthOffset)
        return "\(year(target))年 \(month(target))月"
    }

    func recordsForMonth(offset: Int) -> [WorkRecord] {
        let target = addMonths(Date(), offset: offset)
        let y = year(target)
        let m = month(target)
        return dataManager.records.filter { year($0.date) == y && month($0.date) == m }
    }
}

// ==========================
// MARK: - Previews
// ==========================
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        RootView().environmentObject(DataManager.shared)
    }
}
