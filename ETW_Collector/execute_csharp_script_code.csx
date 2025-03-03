// Add the required libraries
#r "Newtonsoft.Json"
#r "Microsoft.Azure.Workflows.Scripting"

using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Primitives;
using Microsoft.Extensions.Logging;
using Microsoft.Azure.Workflows.Scripting;
using Newtonsoft.Json.Linq;
using Newtonsoft.Json;
using System.Net.Http;
using System.Diagnostics.Tracing;
using System.Text;
using System.Collections.Generic;
using System.Data;
using System.Collections;

/// <summary>
/// Executes the inline csharp code.
/// </summary>
/// <param name="context">The workflow context.</param>
/// <remarks>This is the entry-point to your code.  The function signature should remain unchanged.</remarks>
public static async Task<string> Run(WorkflowContext context, ILogger log)
{
    string LOG_CSV_FILE_PATH = $"C:\\home\\LogFiles\\Trace_event_{DateTime.UtcNow:yyyyMMddHHmmssfff}.log";
    var childFlowUrl = context.GetActionResults("childFlowUrl").GetAwaiter().GetResult().Outputs["childFlowUrl"].ToString();
    
    using var handler = new HttpClientHandler();
    using var client = new HttpClient(handler);
    DataTable _logEntriesDT = new DataTable();
    using var listener = new TextEventListener(_logEntriesDT);

    try
    {
        var response = await client.GetAsync(childFlowUrl);
        var content = await response.Content.ReadAsStringAsync();
    }
    catch (Exception e)
    {
        // Empty catch block - consider adding error handling
    }

    System.IO.File.AppendAllText(LOG_CSV_FILE_PATH, FormatDataTableRow(_logEntriesDT));
    return "Done!";
}

public static string FormatDataTableRow(DataTable dt)
{
    StringBuilder result = new StringBuilder();
    
    // Iterate through each row in the DataTable bb
    for (int rowIndex = 0; rowIndex < dt.Rows.Count; rowIndex++)
    {
        DataRow row = dt.Rows[rowIndex];
        StringBuilder rowString = new StringBuilder();
        
        // Process each column in the row
        for (int colIndex = 0; colIndex < dt.Columns.Count; colIndex++)
        {
            string columnName = dt.Columns[colIndex].ColumnName;
            string value = row[colIndex]?.ToString() ?? "";
            
            if (value.Length == 0)
            {
                continue;
            }

            // Format the column value
            if (colIndex >= 2)
            {
                rowString.Append($"{columnName}={value} ,");
            }
            else
            {
                rowString.Append($"{value} ,");
            }
        }
        
        result.AppendLine(rowString.ToString());
    }
    
    return result.ToString();
}

internal sealed class TextEventListener : EventListener
{
    private DataTable eventTable;
    private readonly Hashtable ignoredList = new Hashtable
    {
        { "Private.InternalDiagnostics.System.Net.Http_decrypt", null },
        { "System.Data.DataCommonEventSource_Trace", null },
        { "System.Buffers.ArrayPoolEventSource", null },
        { "System.Threading.Tasks.TplEventSource", null },
        { "Microsoft-ApplicationInsights-Data", null }
    };
    
    private readonly object _lockObject = new object();
    private const string LOG_FILE_PATH = "C:\\home\\LogFiles\\event_keys.log";

    public TextEventListener(DataTable peventTable)
    {
        eventTable = peventTable;
    }

    private void InitializeDataTableColumns()
    {
        var columns = new[]
        {
            new DataColumn("TimeStamp", typeof(DateTime)),
            new DataColumn("EventName", typeof(string)),
            new DataColumn("OSThreadId", typeof(int)),
            new DataColumn("RelatedActivityId", typeof(Guid)),
            new DataColumn("ActivityId", typeof(Guid)),
            new DataColumn("Message", typeof(string))
        };

        eventTable.Columns.AddRange(columns);
    }

    protected override void OnEventSourceCreated(EventSource eventSource)
    {
        if (ignoredList == null)
        {
            return;
        }

        if (ignoredList.ContainsKey(eventSource.Name))
        {
           EnableEvents(eventSource, EventLevel.Error);
        }
        else
        {
            EnableEvents(eventSource, EventLevel.LogAlways);
        }
    }

    protected override void OnEventWritten(EventWrittenEventArgs eventData)
    {
        var keyToCheck = eventData.EventSource.Name + "_" + eventData.EventName;

        if (ignoredList == null || ignoredList.ContainsKey(keyToCheck))
        {
            return;
        }

        lock (_lockObject)
        {
            if (eventTable == null)
                return;

            if (eventTable.Columns.Count == 0)
            {
                InitializeDataTableColumns();
            }

            DataRow row = eventTable.NewRow();

            // Add the event data to the DataRow
            row["TimeStamp"] = eventData.TimeStamp.ToUniversalTime().ToString();
            row["EventName"] = keyToCheck;
            row["OSThreadId"] = eventData.OSThreadId;
            row["ActivityId"] = eventData.ActivityId;
            row["Message"] = eventData.Message;

            // Add payload data
            for (int i = 0; i < eventData.PayloadNames.Count; i++)
            {
                var payloadName = "Payload"+eventData.PayloadNames[i];
                if (!eventTable.Columns.Contains(payloadName))
                {
                    eventTable.Columns.Add(payloadName, typeof(string));
                }

                var payloadValue = eventData.Payload[i];
                string finalValue;

                if (payloadValue == null)
                {
                    finalValue = string.Empty;
                }
                else if (payloadValue is string stringValue)
                {
                    finalValue = stringValue;
                }
                else
                {
                    try
                    {
                        // Try to serialize non-string objects to JSON
                        finalValue = JsonConvert.SerializeObject(payloadValue, new JsonSerializerSettings 
                        {
                            ReferenceLoopHandling = ReferenceLoopHandling.Ignore,
                            MaxDepth = 10,
                            Formatting = Formatting.None
                        });
                    }
                    catch (Exception ex)
                    {
                        // If serialization fails, use ToString() as fallback
                        finalValue = payloadValue.ToString();
                    }
                }

                row[payloadName] = finalValue;
            }

            eventTable.Rows.Add(row);
        }
    }
}
