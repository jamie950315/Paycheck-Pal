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
    var modified: Bool
    var description: String
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
                HStack {
                    VStack(alignment: .leading) {
                        Text("時薪：\(Int(wagePerHour)) 元")
                            .font(.headline)
                        Text("半小時計算規則：不足0.5小時直接捨棄")
                            .font(.caption)
                    }
                    Spacer()
                    Button("設定") { showingSettings = true }
                }
                .padding()
                Divider()
                ClockPunchView()
                    .padding(.horizontal)
                Divider()
                SummaryView(monthOffset: $monthOffset)
                    .padding(.horizontal)
                Divider()
                RecordsListView(monthOffset: monthOffset)
                Divider()
                Button("Show Log"){
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy/MM/dd (E) HH:mm"
                    for record in dataManager.records {
                        let dateStr = dateFormatter.string(from: record.date)
                        let startStr = dateFormatter.string(from: record.startTime)
                        let endStr = dateFormatter.string(from: record.endTime)
                        print("""
                            --------------------------
                            Date: \(dateStr)
                            Start: \(startStr)
                            End: \(endStr)
                            Hours: \(record.hoursAndMinutesDisplay)
                            HalfHourDecimal: \(String(format: "%.1f", record.halfHourDecimal))
                            Salary: \(Int(record.salary)) 元
                            Hourly: \(Int(record.hourly)) 元
                            Modified: \(record.modified)
                            Description: \(record.description)
                            """)
                    }
                    print("\n\n------------\n\n")
                    print(dataManager.records)
                    
                }
            }
            .navigationTitle("Paycheck Pal")
            .sheet(isPresented: $showingSettings) {
                WageSettingsView()
            }
            .onAppear {
                // first launch: if wage == 0 prompt settings sheet
                if wagePerHour == 0 { showingSettings = true }
            }
        }
    }
}

// ==========================
// MARK: - Wage Settings
// ==========================
struct WageSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("wagePerHour") var wagePerHour: Double = 0.0
    @State private var tempWage: String = ""
    @EnvironmentObject var dataManager: DataManager
    @State private var applyToModified: Bool = false
    
    
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
                if wagePerHour != 0 {
                    
                    Toggle("同步應用到手動修改紀錄", isOn: $applyToModified)
                    
                    Button("應用到本月紀錄") {
                        
                        if let v = Double(tempWage) {
                            wagePerHour = v
                        }
                        
                        let now = Date()
                        let currentMonth = Calendar.current.component(Calendar.Component.month, from: now)
                        let currentYear = Calendar.current.component(Calendar.Component.year, from: now)
                        let formmated = String(format: "%04d/%02d", currentYear, currentMonth)
                        
                        let target = formmated
                              
                        for idx in dataManager.records.indices {
                            
                            let rec = dataManager.records[idx]
                            
                            if yearMonth(rec.date) == target{
                                
                                if applyToModified || !rec.modified{
                                    let newSalary = rec.halfHourDecimal * wagePerHour
                                    let newHourly = wagePerHour
                                    var updated = rec
                                    updated.salary = newSalary
                                    updated.hourly = newHourly
                                    dataManager.records[idx] = updated
                                }
                                
                            }
                            
                        }
                        dataManager.save()
                        presentationMode.wrappedValue.dismiss()
                    }
                    
                    Button("應用到全部紀錄") {
                        
                        if let v = Double(tempWage) {
                            wagePerHour = v
                        }
                        
                        for idx in dataManager.records.indices {
                            
                            let rec = dataManager.records[idx]
                            
                            if applyToModified || !rec.modified{
                                let newHourly = wagePerHour
                                let newSalary = rec.halfHourDecimal * wagePerHour
                                var updated = rec
                                updated.salary = newSalary
                                updated.hourly = newHourly
                                dataManager.records[idx] = updated
                            }
                            
                        }
                        dataManager.save()
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
            }
            .navigationTitle("時薪設定")
            .onAppear { tempWage = wagePerHour == 0 ? "" : String(format: "%.0f", wagePerHour) }
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
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f.string(from: d)
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
        
        let interval = Int(end.timeIntervalSince(start))
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
        
        let record = WorkRecord(date: start.startOfDay(), startTime: start, endTime: end, totalSeconds: interval, hoursAndMinutesDisplay: hAndM, halfHourDecimal: half, salary: salary, hourly: wagePerHour, modified: false, description: "")
        
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
        
        let target = "\(monthLabelFormmatRecord())"
        List {
            Section(header: Text("紀錄")) {
                ForEach(dataManager.records) { rec in
                    
                    if yearMonth(rec.date) == target{
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(shortDate(rec.date))
                                    .font(.headline)
                                Spacer()
                                Text("\(Int(rec.salary)) 元")
                            }
                            HStack {
                                Text("上班：\(timeOnly(rec.startTime))")
                                Text("下班：\(timeOnly(rec.endTime))")
                            }
                            HStack {
                                let formmatedHalfHour = String(format: "%.1f 小時", rec.halfHourDecimal)
                                Text(rec.hoursAndMinutesDisplay)
                                Text("(\(formmatedHalfHour))")
                                Spacer()
                                if rec.modified {
                                    Text("*")
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
    
    func timeOnly(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "hh:mm a"
        return f.string(from: d)
    }
    
    func shortDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd (E)"
        return f.string(from: d)
    }
    
    func yearMonth(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy/MM"
        return f.string(from: d)
    }
    
    func monthLabelFormmatRecord() -> String {
        let now = Date()
        let currentMonth = Calendar.current.component(Calendar.Component.month, from: now)
        let currentYear = Calendar.current.component(Calendar.Component.year, from: now)
        
        var offsettedMonth = currentMonth+monthOffset
        var offsettedYear = currentYear
        
        if offsettedMonth > 12 {
            offsettedYear += 1
            offsettedMonth -= 12
        }
        if offsettedMonth < 1 {
            offsettedYear -= 1
            offsettedMonth += 12
        }
        let formmated = String(format: "%04d/%02d", offsettedYear, offsettedMonth)
        return "\(formmated)"
    }
}

// ==========================
// MARK: - Edit Record
// ==========================
struct EditRecordView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var dataManager: DataManager
    @State var record: WorkRecord
    @State private var tempHourly: String = ""
    @State private var originalHourly: String = ""
    @State private var description: String = ""
    @State private var tempStartTime: Date = Date()
    @State private var tempEndTime: Date = Date()
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("時間")) {
                    DatePicker("上班", selection: $tempStartTime, displayedComponents: [.hourAndMinute, .date])
                    DatePicker("下班", selection: $tempEndTime, displayedComponents: [.hourAndMinute, .date])
                    
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
                                record.modified = true
                            }
                            record.startTime = tempStartTime
                            record.endTime = tempEndTime
                            let interval = Int(record.endTime.timeIntervalSince(record.startTime))
                            record.totalSeconds = max(0, interval)
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
            }
            .navigationTitle("編輯紀錄")
            .onAppear{
                tempHourly = String(format: "%.0f", record.hourly)
                originalHourly = tempHourly
                description = record.description
                tempStartTime = record.startTime
                tempEndTime = record.endTime
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
                    HStack {
                        Text("當月薪資：\(Int(totalSalary)) 元")
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
        let now = Date()
        let currentMonth = Calendar.current.component(Calendar.Component.month, from: now)
        let currentYear = Calendar.current.component(Calendar.Component.year, from: now)
        
        var offsettedMonth = currentMonth+monthOffset
        var offsettedYear = currentYear
        
        if offsettedMonth > 12 {
            offsettedYear += 1
            offsettedMonth -= 12
        }
        if offsettedMonth < 1 {
            offsettedYear -= 1
            offsettedMonth += 12
        }

        return "\(offsettedYear)年 \(offsettedMonth)月"
    }
    
    func recordsForMonth(offset: Int) -> [WorkRecord] {
        let cal = Calendar.current
        guard let target = cal.date(byAdding: .month, value: offset, to: Date()) else { return [] }
        let year = cal.component(.year, from: target)
        let month = cal.component(.month, from: target)
        return dataManager.records.filter {
            let compYear = cal.component(.year, from: $0.date)
            let compMonth = cal.component(.month, from: $0.date)
            return compYear == year && compMonth == month
        }
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
