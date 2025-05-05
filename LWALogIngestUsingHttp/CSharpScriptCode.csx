// Add the required libraries
#r "Newtonsoft.Json"
#r "Microsoft.Azure.Workflows.Scripting"
#r "System.Security.Cryptography"

using Microsoft.Azure.Workflows.Scripting;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using System;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

/// <summary>
/// Executes the inline csharp code.  
/// </summary>
/// <param name="context">The workflow context.</param>
/// <remarks> This is the entry-point to your code. The function signature should remain unchanged.</remarks>
public static async Task<Results> Run(WorkflowContext context, ILogger log)
{
    try
    {
        var jsonData = (await context.GetActionResults("payload_to_send").ConfigureAwait(false)).Outputs.ToString(Formatting.None);
        var connection = (await context.GetActionResults("LAW_connection").ConfigureAwait(false)).Outputs["body"].ToObject<LogAnalyticsConnection>();

        string dateString = DateTime.UtcNow.ToString("r");
        byte[] content = Encoding.UTF8.GetBytes(jsonData);
        int contentLength = content.Length;

        string method = "POST";
        string contentType = "application/json";
        string resource = "/api/logs";
        string stringToSign = $"{method}\n{contentLength}\n{contentType}\nx-ms-date:{dateString}\n{resource}";
       
        byte[] sharedKeyBytes = Convert.FromBase64String(connection.SharedKey);

        using HMACSHA256 hmac = new HMACSHA256(sharedKeyBytes);
        byte[] stringToSignBytes = Encoding.UTF8.GetBytes(stringToSign);
        byte[] signatureBytes = hmac.ComputeHash(stringToSignBytes);
        string signature = Convert.ToBase64String(signatureBytes); 
        
        return new Results
        {
            signature = $"SharedKey {connection.WorkspaceId}:{signature}",
            dateString = dateString,
            debug = $"{contentLength} {jsonData}" 
        };
    }
    catch (Exception ex)
    {
        return new Results
        {
            debug = $"{ex.Message}" 
        };
    }
}

public class LogAnalyticsConnection
{
    public string WorkspaceId { get; set; }
    public string SharedKey { get; set; }
}

public class Results
{
    public string signature { get; set; }
    public string dateString { get; set; }
    public string debug { get; set; }
}