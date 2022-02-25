//
/*
Copyright 2021 Splunk Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
	

import Foundation
import CoreData
import OpenTelemetryApi
import OpenTelemetrySdk
import SwiftUI
import ZipkinExporter

let FLUSH_OUT_TIME_SECONDS = 60   // 4 * 60 * 60  // 4 hours
let FLUSH_OUT_MAX_SIZE = 21966080  // 20 MB

let Entity_name = "Pending"
let TimeStampColumn = "created_at"
let ENTITY_NAME = "PendingSpans"



public class CoreDataManager {
    public static let shared = CoreDataManager()
    let identifier: String  = "com.splunk.opentelemetry.SplunkRum"       // splunkrum framework bundle ID
    let model: String       = "Rum"                      // Model name
    
    lazy var persistentContainer: NSPersistentContainer = {
    
            let messageKitBundle = Bundle(identifier: self.identifier)
            let modelURL = messageKitBundle!.url(forResource: self.model, withExtension: "momd")!
            let managedObjectModel =  NSManagedObjectModel(contentsOf: modelURL)
        
            let storedescription = NSPersistentStoreDescription(url: NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("Rum.sqlite"))
            storedescription.setOption(true as NSNumber, forKey: NSSQLiteManualVacuumOption)
       
            let container = NSPersistentContainer(name: self.model, managedObjectModel: managedObjectModel!)
            container.persistentStoreDescriptions = [storedescription]
            container.loadPersistentStores { (storeDescription, error) in
                 
                if let err = error{
                    fatalError("Loading of store failed:\(err)")
                }
            }
            
            return container
        }()
    
    //MARK: - Insert seperate value -
    public func insertSpanValue(_ spans: [SpanData]) {
        let managedObjectContext = persistentContainer.viewContext
        let spanEntity = NSEntityDescription.entity(forEntityName: ENTITY_NAME, in: managedObjectContext)!
        for pendingSpan in spans {
            let span = NSManagedObject(entity: spanEntity, insertInto: managedObjectContext)
            let encoder = JSONEncoder()
            if let jsonData = try? encoder.encode(pendingSpan.attributes) {
                if let jsonString = String(data: jsonData, encoding: . utf8) {
                    print(jsonString)
                    span.setValue(jsonString, forKey: "attributes")
                    
                }
            }
            
           
            span.setValue(String(describing: pendingSpan.events), forKey: "events")
            span.setValue(pendingSpan.endTime, forKey: "duration")
            span.setValue(String(describing:pendingSpan.kind), forKey: "kind")
            span.setValue(String(describing:pendingSpan.parentSpanId), forKey: "parentSpanId")
            span.setValue(String(describing:pendingSpan.spanId), forKey: "spanId")
            span.setValue(pendingSpan.name, forKey: "spanName")
            span.setValue(pendingSpan.startTime, forKey: "start")
            span.setValue(String(describing:pendingSpan.traceFlags), forKey: "traceFlags")
            span.setValue(String(describing:pendingSpan.traceId), forKey: "traceId")
            span.setValue(String(describing:pendingSpan.traceState), forKey: "traceState")
            span.setValue(Date(), forKey: TimeStampColumn)  // this is used only for flush out
           
            // save in to db
            do {
                try managedObjectContext.save()
            } catch let error as NSError {
                print("could not save. \(error) \(error.userInfo)")
            }
        }
    }
   // public func fetchSpanValues() {
    public func fetchSpanValues()->[SpanData] {
        let managedObjectContext = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: ENTITY_NAME)
        var newSpans = [SpanData]()
        do {
            let spans = try managedObjectContext.fetch(fetchRequest) as! [NSManagedObject]
            for span in spans as [NSManagedObject] {
                print(span)
                newSpans.append(createNewSpan(using: span))
               // createNewSpan(using: span)
            }
        } catch {
            print(error)
        }
        return newSpans
   }
    func createNewSpan(using spanInfo: NSManagedObject) -> SpanData {
   // func createNewSpan(using spanInfo: NSManagedObject) {
        let tracer = buildTracer()
        let span = tracer.spanBuilder(spanName:spanInfo.value(forKey: "spanName") as! String).setStartTime(time: spanInfo.value(forKey: "start") as! Date).startSpan()
       // span.addEvent(name: spanInfo.value(forKey: "events") as! String)
        //.setSpanKind(spanKind: spanInfo.value(forKey: "kind") as! SpanKind )
        let attributesDict = convertStringToDictionary(text: spanInfo.value(forKey: "attributes") as! String)
        for dict in attributesDict! {
          //  span.setAttribute(key: dict.key, value: dict.value as! String)
            print(dict)
        }
        span.end(time: spanInfo.value(forKey: "duration") as! Date)
        return (span as! RecordEventsReadableSpan).toSpanData()
    }
    func convertStringToDictionary(text: String) -> [String:AnyObject]? {
        if let data = text.data(using: .utf8) {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:AnyObject]
                return json
            } catch {
                print("Something went wrong")
            }
        }
        return nil
    }
//MARK:- Insert span in to DB
    /*func encodeSpans(spans: [SpanData]) -> [ZipkinSpan] {
        return spans.map { ZipkinConversionExtension.toZipkinSpan(otelSpan: $0, defaultLocalEndpoint: localEndPoint) }
    }*/
    public func insertReadableSpabIntoDB(_ spans: [SpanData]){
        
        let managedObject = persistentContainer.viewContext
        let spanEntity = NSEntityDescription.entity(forEntityName: "ReadableSpans", in: managedObject)!
       // let spans = encodeSpans(spans: spans)
        //insert record logic
        for pendingSpan in spans {
            let span = NSManagedObject(entity: spanEntity, insertInto: managedObject)
          
            do {
                let jsonEncoder = JSONEncoder()
                let jsonData = try jsonEncoder.encode(SpanExporterData(span: pendingSpan))
                if let json = String(data: jsonData, encoding: .utf8) {
                    print(json)
                    span.setValue(json, forKey: "rSpan")
                    span.setValue(Date(), forKey: TimeStampColumn)
                    
                }
            } catch {
                print(error)
            }
            
            
          /*  let str = String(describing: pendingSpan)
            print(str)
            // add try to convert str in to span data logic here
            span.setValue(String(describing: pendingSpan), forKey: "rSpan")
            span.setValue(Date(), forKey: TimeStampColumn)*/
            
            // new logic
            // convert struct in to jsonstring then save to db
           // let jsonStr = pendingSpan.toJson()
           // print(jsonStr)
           // let spandataFromJSON: SpanData? = instantiate(jsonString: jsonStr)
          //  print(spandataFromJSON!)
            do {
                try managedObject.save()
                
            } catch let error as NSError {
                print("could not save. \(error) \(error.userInfo)")
            }
        }
    }
   
        /*return SpanData(traceId: TraceId(),
                               spanId: SpanId(),
                               traceFlags: TraceFlags(),
                               traceState: TraceState(),
                               resource: Resource(),
                               instrumentationLibraryInfo: InstrumentationLibraryInfo(),
                               name: "spanName",
                               kind: .server,
                               startTime: Date(timeIntervalSinceReferenceDate: 3000),
                               endTime: Date(timeIntervalSinceReferenceDate: 3001),
                               hasRemoteParent: false)*/
       
   
  
  /*  public func export(spans: [SpanData]) {
            Opentelemetry_Proto_Collector
            let exportRequest = Opentelemetry_Proto_Collector_Trace_V1_ExportTraceServiceRequest.with {
                $0.resourceSpans = SpanAdapter.toProtoResourceSpans(spanDataList: spans)
            }
            
            do {
                let jsonData = try exportRequest.jsonUTF8Data()
                do {
                    let span = try JSONDecoder().decode(OtlpSpan.self, from: jsonData)
                    exportedSpans.append(span)
                } catch {
                    print("Decode Error: \(error)")
                }
                return .success
            } catch {
                return .failure
            }
        }*/
    public func fetchReadableSpanFromDB() -> [SpanData] {
            let managedObjectContext = persistentContainer.viewContext
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ReadableSpans")
            let result = [SpanData]()
            do {
                //let  result1 = try managedObject.fetch(fetchRequest)
                //print(result1)
               let result1 = try managedObjectContext.fetch(fetchRequest) as! [NSManagedObject]
                for data in result1 {
                    /*var d = String(describing: data.value(forKey: "rSpan")!)
                    print("\(d)")
                    
                    let T = String(describing: data.value(forKey: "created_at")!)
                    print("\(T)")
                    d.remove(at: d.index(before: d.endIndex))
                    d = d.replacingOccurrences(of: "SpanData(", with: "")
                    print("now string is ////// \(d)")*/
                    
                    let jsonString = data.value(forKey: "rSpan")! as! String
                    let jsonData = Data(jsonString.utf8)
                    let decoder = JSONDecoder()

                    do {
                        let span = try decoder.decode(SpanExporterData.self, from: jsonData)
                        print(span)
                       // print("Stat time  == \(span.start as Date)")
                       print("TraceID == \(TraceId(fromHexString: span.traceId))")
                     //   result.append(SpanData(traceId:TraceId(fromHexString: span.traceId), spanId:SpanId(id: span.spanId as! UInt64), name:span.span, kind:SpanKind(rawValue: span.spanKind)!, startTime: span.start as Date, endTime:span.duration as! Date))
                    } catch {
                        print(error.localizedDescription)
                    }
                  
                }
            } catch {
                print("failed")
                return result
            }
            return result
        }
public func insertSpanIntoDB(_ spans: [SpanData]) {
    getStoreInformation()
   
    let spanArr : Array = [1,2,3,4]
   // let spanArr : Array = [spans]
    let managedObject = persistentContainer.newBackgroundContext()

    let spanEntity = NSEntityDescription.entity(forEntityName: Entity_name, in: managedObject)!
    
    //let encodedData = NSKeyedArchiver.archivedData(withRootObject: spanArr)
    let encodedData = NSKeyedArchiver.archivedData(withRootObject: spanArr)
    let span = NSManagedObject(entity: spanEntity, insertInto: managedObject)
    span.setValue(encodedData, forKey: "span")
    span.setValue(Date(), forKey: TimeStampColumn)
    do {
        try managedObject.save()
        
    } catch let error as NSError {
        print("could not save. \(error) \(error.userInfo)")
    }
}
    //MARK:- fetch span from DB
public func fetchSpanFromDB() -> [SpanData] {
    let managedObjectContext = persistentContainer.newBackgroundContext()
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: Entity_name)
    let result = [SpanData]()
    do {
        let result1 = try managedObjectContext.fetch(fetchRequest) as! [Pending]
        for data in result1 {
           // guard let spanDataArray = (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data.span!)) as? [SpanData] else { return [] }
            guard (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data.span!)) != nil else { return [] }
           
           /* guard let spanDataArray = (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data.span!)) else { return [] }
           
            print("out put is/////////// \(spanDataArray)")*/
           
          
        }
    } catch {
        print("failed")
        return result
    }
    
    
    
      /*  do {
            //let  result1 = try managedObject.fetch(fetchRequest)
            //print(result1)
           let result1 = try managedObjectContext.fetch(fetchRequest) as! [Pending]
            for data in result1 {
                let d = String(describing: data.span ?? "")
                print("\(d)")
                
                let T = String(describing: data.created_at)
                print("\(T)")
              
            }
        } catch {
            print("failed")
            return result
        }*/
        return result
    }
    //MARK: - Flush out logic -
    /** flush out db after 4 h time out */
    public func flushOutSpanAfterTimePeriod() {
        print("Core Data Store at ......\(NSPersistentContainer.defaultDirectoryURL().absoluteString)")
        let managedObjectContext = persistentContainer.newBackgroundContext()
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: Entity_name)
        // Add Predicate
        let flushDBTime = Date().addingTimeInterval(TimeInterval(-FLUSH_OUT_TIME_SECONDS))
        let predicate = NSPredicate(format: "\(TimeStampColumn) < %@", flushDBTime as CVarArg)
        fetchRequest.predicate = predicate
        
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        do {
           try managedObjectContext.executeAndMergeChanges(using: batchDeleteRequest)
        } catch {
            print(error)
        }
        
        /*do {
            let records = try managedObjectContext.fetch(fetchRequest) as! [Pending]

            for record in records {
                managedObjectContext.delete(record)
            }

        } catch {
            print(error)
        }
        
        do {
            try managedObjectContext.save()
            
        } catch let error as NSError {
            print("could not save. \(error) \(error.userInfo)")
        }*/
        
        
    }
    /** delete record of db if db size exceed then max size*/
    public func flushDbIfSizeExceed() {
       /* let dbsize = getPersistentStoreSize() as! Int
        if dbsize > FLUSH_OUT_MAX_SIZE {
            deleteSpanInFifoManner()
        }*/
    }
    /**delete db record in FIFO manner and vaccume space**/
    public func deleteSpanInFifoManner() {
        getStoreInformation()
        let managedObjectContext = persistentContainer.viewContext
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: Entity_name)
        
        // Add Sort Descriptor
        let sortDescriptor = NSSortDescriptor(key: TimeStampColumn, ascending: true)
        fetchRequest.sortDescriptors = [sortDescriptor]
        fetchRequest.fetchLimit = 1000
        
        do {
            let records = try managedObjectContext.fetch(fetchRequest) as! [Pending]

            for record in records {
                managedObjectContext.delete(record)
            }

        } catch {
            print(error)
        }
        
        do {
            try managedObjectContext.save()
            
        } catch let error as NSError {
            print("could not save. \(error) \(error.userInfo)")
            
        }
        getStoreInformation()
       
    }
    // single spandata delete.
    public func deleteSpanData(spans : [SpanData]) {
        getStoreInformation()
        let managedObjectContext = persistentContainer.newBackgroundContext()
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: Entity_name)
        
        for span in spans {
            // Add Predicate
            let predicate = NSPredicate(format: "span == %@", span as! CVarArg)
            fetchRequest.predicate = predicate
            
            do {
                let records = try managedObjectContext.fetch(fetchRequest) as! [NSManagedObject]

                for record in records {
                    managedObjectContext.delete(record)
                }

            } catch {
                print(error)
            }
        }
       
        // save context.
        do {
            try managedObjectContext.save()
            
        } catch let error as NSError {
            print("could not save. \(error) \(error.userInfo)")
        }
    }
    
    public func timeWiseSorting() {
        
        let managedObjectContext = persistentContainer.newBackgroundContext()
        // Create Fetch Request
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: Entity_name)

        // Add Sort Descriptor
        let sortDescriptor = NSSortDescriptor(key: TimeStampColumn, ascending: true)
        fetchRequest.sortDescriptors = [sortDescriptor]

        do {
            let records = try managedObjectContext.fetch(fetchRequest) as! [NSManagedObject]

            for record in records {
                print(record.value(forKey: TimeStampColumn) ?? "no time")
            }

        } catch {
            print(error)
        }
    }
    /**get used space and free space information**/
    public func getPersistentStoreSize()-> Any {
        let defaultdirecotry = NSPersistentContainer.defaultDirectoryURL()
        let persistentStorePath = defaultdirecotry.appendingPathComponent("Rum.sqlite").path
        
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: persistentStorePath) as NSDictionary
            print("Persistent store size: \(String(describing: fileAttributes.object(forKey: FileAttributeKey.size))) bytes")
            return fileAttributes.object(forKey: FileAttributeKey.size) as Any
        } catch {
            print("FileAttribute error: \(error)")
            return error
        }
        
    }
    public func getStoreInformation() {
        let defaultdirecotry = NSPersistentContainer.defaultDirectoryURL()
        let persistentStorePath = defaultdirecotry.appendingPathComponent("Rum.sqlite").path
        
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: persistentStorePath) as NSDictionary
            print("Persistent store size: \(String(describing: fileAttributes.object(forKey: FileAttributeKey.size))) bytes")
        } catch {
            print("FileAttribute error: \(error)")
        }
        
        do {
            let fileSystemAttributes = try FileManager.default.attributesOfFileSystem(forPath: persistentStorePath) as NSDictionary
            print("Free space on Device: \(String(describing: fileSystemAttributes.object(forKey:FileAttributeKey.systemFreeSize))) bytes")
            print("Size of Device: \(String(describing: fileSystemAttributes.object(forKey:FileAttributeKey.systemSize))) bytes")
        } catch {
            print("FileAttribute error: \(error)")
        }
        
       
    }
    
}
//MARK: -
extension String {
    func toJSON() -> Any? {
        guard let data = self.data(using: .utf8, allowLossyConversion: false) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: .mutableContainers)
    }
}

/*class ManagedSpan: NSManagedObject {

    @NSManaged var traceId: String
    @NSManaged var spanId: String
    @NSManaged var name: String
    @NSManaged var kind: String
    @NSManaged var startTime: String
    @NSManaged var endTime: String

    var spandata: SpanData {
       get {
            return SpanData(traceId: traceId, spanId: spanId, name: name, kind: kind, startTime: startTime, endTime: endTime)
       }
       set {
            self.name = newValue.name
       }
     }
}*/
/*class DecodedSpanData: Decodable {
    var spandata: SpanData
    
    init(spandata: SpanData) {
        self.spandata = spandata
    }
    required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let traceId = try container.decode(String.self, forKey: .traceId)
            spandata = SpanData(traceId:traceId )
            
        }
        
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(spandata.traceId, forKey: .traceId) // Might want to make sure that the name is not nil here
    }
        
        enum CodingKeys: String, CodingKey {
            case traceId
            
        }
}*/
/*extension SpanData: Codable {
    public init(from decoder: Decoder) throws {
        print("decoder")
    }
    
   
   public func encode(to encoder: Encoder) throws {
        print("Encode")
    }
    
    func toJson()->String {
        let jsonEncoder = JSONEncoder()
        let jsonData = try! jsonEncoder.encode(self)
        let jsonString = String(data: jsonData, encoding: .utf8)
        return jsonString!
    }
}

extension Encodable {
    
    func toJSONString() -> String {
        let jsonData = try! JSONEncoder().encode(self)
        return String(data: jsonData, encoding: .utf8)!
    }
    
}

func instantiate<T: Decodable>(jsonString: String) -> T? {
    return try? JSONDecoder().decode(T.self, from: jsonString.data(using: .utf8)!)
}*/
func getDocumentsDirectory() -> URL {
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let documentsDirectory = paths[0]
    return documentsDirectory
}
func getLibraryDirectory() -> URL {
    let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    let librarysDirectory = paths[0]
    return librarysDirectory
}
extension NSManagedObjectContext {
    
    /// Executes the given `NSBatchDeleteRequest` and directly merges the changes to bring the given managed object context up to date.
    ///
    /// - Parameter batchDeleteRequest: The `NSBatchDeleteRequest` to execute.
    /// - Throws: An error if anything went wrong executing the batch deletion.
    public func executeAndMergeChanges(using batchDeleteRequest: NSBatchDeleteRequest) throws {
        batchDeleteRequest.resultType = .resultTypeObjectIDs
        do {
            let result = try execute(batchDeleteRequest) as? NSBatchDeleteResult
            let changes: [AnyHashable: Any] = [NSDeletedObjectsKey: result?.result as? [NSManagedObjectID] ?? []]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self])
        } catch {
            print(error)
        }
        
    }
}
//MARK: -
class SpanExporterData: Encodable ,Decodable{
    public let span: String
    public let traceId: String
    public let spanId: String
    public let spanKind: String
   // public let traceFlags: TraceFlags
   // public let traceState: TraceState
    public let parentSpanId: String?
    public let start: Date
    public let duration: TimeInterval
   // public let attributes: [String: AttributeValue]

    init(span: SpanData) {
        self.span = span.name
        self.traceId = span.traceId.hexString
        self.spanId = span.spanId.hexString
        self.spanKind = span.kind.rawValue
      //  self.traceFlags = span.traceFlags
      //  self.traceState = span.traceState
        self.parentSpanId = span.parentSpanId?.hexString ?? SpanId.invalid.hexString
        self.start = span.startTime
        self.duration = span.endTime.timeIntervalSince(span.startTime)
       // self.attributes = span.attributes
    }
    
   /* enum CodingKeys: String, CodingKey {
        case traceId
        case spanId
        case traceFlags
        case traceState
        case parentSpanId
        case resource
        case instrumentationLibraryInfo
        case name
        case start
        case attributes
        case events
        case links
        case status
        case duration
        case span
        case spanKind
        case hasRemoteParent
        case hasEnded
        case totalRecordedEvents
        case totalRecordedLinks
        case totalAttributeCount
    }
    
    required init(from decoder:Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            span = try values.decode(String.self, forKey: .span)
            traceId = try values.decode(String.self, forKey: .traceId)
        }*/
}
func instantiate<T: Decodable>(jsonString: String) -> T? {
    return try? JSONDecoder().decode(T.self, from: jsonString.data(using: .utf8)!)
}
/*extension SpanData {
   init(record: SpanData) {
       self.settingTraceId(record.traceId)
       self.settingSpanId(record.spanId)
       self.settingTraceFlags(record.traceFlags)
       self.settingTraceState(record.traceState)
       self.settingParentSpanId(record.parentSpanId!)
       self.settingResource(record.resource)
       self.settingName(record.name)
       self.settingKind(record.kind)
       self.settingStartTime(record.startTime)
       self.settingAttributes(record.attributes)
       self.settingEvents(record.events)
       self.settingLinks(record.links)
       self.settingEndTime(record.endTime)
       self.settingStatus(record.status)
       self.settingHasRemoteParent(record.hasRemoteParent)
       self.settingHasEnded(record.hasEnded)
       self.settingTotalRecordedEvents(record.totalRecordedEvents)
       self.settingTotalRecordedLinks(record.totalRecordedLinks)
       self.settingTotalAttributeCount(record.totalAttributeCount)
       // self.instrumentationLibraryInfo = InstrumentationLibraryInfo()
 }
}*/
/*extension SpanData {
    public init(traceId: TraceId, spanId: SpanId, traceFlags: TraceFlags = TraceFlags(), traceState: TraceState = TraceState(), parentSpanId: SpanId? = nil, resource: Resource = Resource(), instrumentationLibraryInfo: InstrumentationLibraryInfo = InstrumentationLibraryInfo(), name: String, kind: SpanKind, startTime: Date, attributes: [String : AttributeValue] = [String: AttributeValue](), events: [SpanData.Event] = [Event](), links: [SpanData.Link] = [Link](), status: Status = .unset, endTime: Date, hasRemoteParent: Bool = false, hasEnded: Bool = false, totalRecordedEvents: Int = 0, totalRecordedLinks: Int = 0, totalAttributeCount: Int = 0) {
        self.init(traceId: traceId, spanId: spanId, name: name, kind: kind, startTime: startTime, endTime: endTime)
       
        self.settingTraceFlags(traceFlags)
        self.settingTraceState(traceState)
        self.settingParentSpanId(parentSpanId!)
        self.settingResource(resource)
        self.settingAttributes(attributes)
        self.settingEvents(events)
        self.settingLinks(links)
        self.settingStatus(status)
        self.settingHasRemoteParent(hasRemoteParent)
        self.settingHasEnded(hasEnded)
        self.settingTotalRecordedEvents(totalRecordedEvents)
        self.settingTotalRecordedLinks(totalRecordedLinks)
        self.settingTotalAttributeCount(totalAttributeCount)
    }
}*/
/*class SpanDataContainer : Codable {
    var spandata: SpanData
    
    init(spandata: SpanData) {
        self.spandata = spandata
    }
    required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let traceId = try container.decode(TraceId.self, forKey: .traceId)
            let spanId = try container.decode(SpanId.self, forKey: .spanId)
        
            spandata = SpanData(traceId: traceId, spanId: spanId, traceFlags: <#T##TraceFlags#>, traceState: <#T##TraceState#>, parentSpanId: <#T##SpanId?#>, resource: <#T##Resource#>, instrumentationLibraryInfo: <#T##InstrumentationLibraryInfo#>, name: <#T##String#>, kind: <#T##SpanKind#>, startTime: <#T##Date#>, attributes: <#T##[String : AttributeValue]#>, events: <#T##[SpanData.Event]#>, links: <#T##[SpanData.Link]#>, status: <#T##Status#>, endTime: <#T##Date#>, hasRemoteParent: <#T##Bool#>, hasEnded: <#T##Bool#>, totalRecordedEvents: <#T##Int#>, totalRecordedLinks: <#T##Int#>, totalAttributeCount: <#T##Int#>)
            
        }
        
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
      //  try container.encode(spandata.traceId, forKey: .traceId) // Might want to make sure that the name is not nil here
    }
        
        enum CodingKeys: String, CodingKey {
            case traceId
            case spanId
            case traceFlags
            case traceState
            case parentSpanId
            case resource
            case instrumentationLibraryInfo
            case name
            case startTime
            case attributes
            case events
            case links
            case status
            case endTime
            case hasRemoteParent
            case hasEnded
            case totalRecordedEvents
            case totalRecordedLinks
            case totalAttributeCount
        }
}*/
