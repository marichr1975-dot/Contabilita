import Foundation
import ZIPFoundation

struct ExcelAnalysisDay {
    let date: Date
    let rows: [PDFAnalysisRow]
}

final class ExcelAnalysis {
    static func analizza(file: URL) -> [ExcelAnalysisDay]? {
        guard file.pathExtension.lowercased() == "xlsx" else { return nil }

        let archive: Archive
        do { archive = try Archive(url: file, accessMode: .read) }
        catch { return nil }

        let shared = sharedStrings(archive)
        let sheets = archive.filter {
            $0.path.hasPrefix("xl/worksheets/") && $0.path.hasSuffix(".xml")
        }.map(\.path).sorted()

        for path in sheets {
            guard let data = read(archive, path),
                  let rows = parseRows(data, shared: shared),
                  let result = parseWorkbook(rows),
                  !result.isEmpty else { continue }
            return result
        }
        return nil
    }

    private static func parseWorkbook(_ rows: [[String]]) -> [ExcelAnalysisDay]? {
        func norm(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
             .replacingOccurrences(of: " ", with: "")
             .replacingOccurrences(of: "_", with: "")
             .replacingOccurrences(of: "-", with: "")
             .replacingOccurrences(of: ".", with: "")
        }

        var header = -1
        var dateCol = -1
        var articleCols: [(Int,String)] = []

        for (i,row) in rows.enumerated() {
            guard let d = row.firstIndex(where: {
                let n=norm($0); return n=="data" || n.contains("data")
            }) else { continue }

            var cols:[(Int,String)] = []
            for (j,v) in row.enumerated() where j != d {
                let name=v.trimmingCharacters(in:.whitespacesAndNewlines)
                let n=norm(name)
                guard !name.isEmpty,
                      !n.contains("prezzounitario"),
                      !n.contains("totalepezzi"),
                      !n.contains("totaleeuro"),
                      !n.contains("totalegenerale") else { continue }
                cols.append((j,name))
            }
            if !cols.isEmpty { header=i; dateCol=d; articleCols=cols; break }
        }

        guard header >= 0 else { return nil }

        var prices:[Int:Double]=[:]
        if header > 0 {
            for (c,_) in articleCols where c < rows[header-1].count {
                if let n=number(rows[header-1][c]) { prices[c]=n }
            }
        }

        var grouped:[Date:[PDFAnalysisRow]] = [:]
        for row in rows.dropFirst(header+1) {
            guard dateCol < row.count, let d=date(row[dateCol]) else { continue }
            var day:[PDFAnalysisRow]=[]
            for (c,name) in articleCols where c < row.count {
                guard let q=number(row[c]), q > 0 else { continue }
                let quantity=Int(q.rounded())
                guard quantity > 0 else { continue }
                let price=prices[c]
                day.append(PDFAnalysisRow(article:name, quantity:quantity,
                                          unitPrice:price,
                                          total:price.map{Double(quantity)*$0}))
            }
            if !day.isEmpty { grouped[Calendar.current.startOfDay(for:d),default:[]] += day }
        }

        return grouped.keys.sorted().map { ExcelAnalysisDay(date:$0,rows:grouped[$0] ?? []) }
    }

    private static func number(_ s:String)->Double? {
        let x=s.trimmingCharacters(in:.whitespacesAndNewlines)
            .replacingOccurrences(of:"€",with:"").replacingOccurrences(of:" ",with:"")
        if let n=Double(x){return n}
        return Double(x.replacingOccurrences(of:".",with:"").replacingOccurrences(of:",",with:"."))
    }

    private static func date(_ s:String)->Date? {
        let x=s.trimmingCharacters(in:.whitespacesAndNewlines)
        let f=DateFormatter(); f.locale=Locale(identifier:"it_IT")
        for fmt in ["dd/MM/yyyy","dd-MM-yyyy","dd.MM.yyyy","d/M/yyyy","d-M-yyyy","d.M.yyyy"] {
            f.dateFormat=fmt
            if let d=f.date(from:x){return d}
        }
        if let serial=Double(x), serial >= 30000, serial <= 60000 {
            var c=DateComponents(); c.year=1899;c.month=12;c.day=30
            if let base=Calendar(identifier:.gregorian).date(from:c) {
                return Calendar(identifier:.gregorian).date(byAdding:.day,value:Int(serial.rounded()),to:base)
            }
        }
        return nil
    }

    private static func read(_ a:Archive,_ path:String)->Data? {
        guard let e=a[path] else{return nil}; var d=Data()
        do { try a.extract(e){d.append($0)}; return d } catch{return nil}
    }

    private static func sharedStrings(_ a:Archive)->[String] {
        guard let d=read(a,"xl/sharedStrings.xml"),
              let x=String(data:d,encoding:.utf8) else{return[]}
        let si=try?NSRegularExpression(pattern:#"<si\b[^>]*>(.*?)</si>"#,options:.dotMatchesLineSeparators)
        let tr=try?NSRegularExpression(pattern:#"<t\b[^>]*>(.*?)</t>"#,options:.dotMatchesLineSeparators)
        guard let si,tr else{return[]}
        let ns=x as NSString; var out:[String]=[]
        for m in si.matches(in:x,range:NSRange(location:0,length:ns.length)){
            let b=ns.substring(with:m.range(at:1)) as NSString; var t=""
            for tm in tr.matches(in:b as String,range:NSRange(location:0,length:b.length)){
                t += xml(b.substring(with:tm.range(at:1)))
            }
            out.append(t)
        }
        return out
    }

    private static func parseRows(_ d:Data,shared:[String])->[[String]]? {
        guard let x=String(data:d,encoding:.utf8) else{return nil}
        let rr=try?NSRegularExpression(pattern:#"<row\b[^>]*>(.*?)</row>"#,options:.dotMatchesLineSeparators)
        let cr=try?NSRegularExpression(pattern:#"<c\b([^>]*)>(.*?)</c>"#,options:.dotMatchesLineSeparators)
        guard let rr,cr else{return nil}
        let ns=x as NSString; var out:[[String]]=[]
        for rm in rr.matches(in:x,range:NSRange(location:0,length:ns.length)){
            let body=ns.substring(with:rm.range(at:1)) as NSString
            var cells:[(Int,String)]=[]
            for cm in cr.matches(in:body as String,range:NSRange(location:0,length:body.length)){
                let a=body.substring(with:cm.range(at:1)); let b=body.substring(with:cm.range(at:2))
                let ref=attr(a,"r") ?? "A1"; let type=attr(a,"t")
                var v=tag(b,"v") ?? ""
                if type=="s",let i=Int(v),i>=0,i<shared.count{v=shared[i]}
                if type=="inlineStr"{v=tag(b,"t") ?? v}
                cells.append((column(String(ref.prefix{$0.isLetter})),xml(v)))
            }
            guard let max=cells.map({$0.0}).max() else{continue}
            var row=Array(repeating:"",count:max+1)
            for (i,v) in cells{row[i]=v}; out.append(row)
        }
        return out
    }

    private static func attr(_ s:String,_ n:String)->String? {
        let r=try?NSRegularExpression(pattern:#"\b"# + NSRegularExpression.escapedPattern(for:n)+#"="([^"]+)""#)
        guard let r,m=r.firstMatch(in:s,range:NSRange(s.startIndex...,in:s)) else{return nil}
        return (s as NSString).substring(with:m.range(at:1))
    }
    private static func tag(_ s:String,_ n:String)->String? {
        let r=try?NSRegularExpression(pattern:#"<"# + NSRegularExpression.escapedPattern(for:n)+#"[^>]*>(.*?)</"# + NSRegularExpression.escapedPattern(for:n)+#">"#,options:.dotMatchesLineSeparators)
        guard let r,m=r.firstMatch(in:s,range:NSRange(s.startIndex...,in:s)) else{return nil}
        return (s as NSString).substring(with:m.range(at:1))
    }
    private static func column(_ s:String)->Int {
        var v=0
        for u in s.uppercased().unicodeScalars where u.value>=65 && u.value<=90 {v=v*26+Int(u.value-64)}
        return max(0,v-1)
    }
    private static func xml(_ s:String)->String {
        s.replacingOccurrences(of:"&amp;",with:"&").replacingOccurrences(of:"&lt;",with:"<")
         .replacingOccurrences(of:"&gt;",with:">").replacingOccurrences(of:"&quot;",with:"\"")
         .replacingOccurrences(of:"&apos;",with:"'")
    }
}
