const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();
const sqs = new AWS.SQS();

exports.handler = async (event) => {
  try {
    // Assuming the event contains the document data
    const { customerId, documentLocation, metadata } = JSON.parse(event.body);
    
    // Generate a unique ID for the document
    const documentId = `doc_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    // Prepare the DynamoDB item
    const item = {
      id: documentId,
      customer_id: customerId,
      s3_location: documentLocation,
      metadata: metadata || {},
      created_at: new Date().toISOString()
    };
    
    // Write to DynamoDB
    await dynamodb.put({
      TableName: process.env.DYNAMODB_TABLE,
      Item: item
    }).promise();
    
    // Prepare SQS message
    const sqsMessage = {
      documentId,
      customerId,
      documentLocation,
      metadata,
      timestamp: new Date().toISOString()
    };
    
    // Send message to SQS
    await sqs.sendMessage({
      QueueUrl: process.env.SQS_QUEUE_URL,
      MessageBody: JSON.stringify(sqsMessage),
      MessageAttributes: {
        "DocumentType": {
          DataType: "String",
          StringValue: "RAG"
        }
      }
    }).promise();
    
    return {
      statusCode: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
      },
      body: JSON.stringify({
        message: "Document processed successfully",
        documentId: documentId
      })
    };
    
  } catch (error) {
    console.error('Error processing document:', error);
    
    return {
      statusCode: 500,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
      },
      body: JSON.stringify({
        message: "Error processing document",
        error: error.message
      })
    };
  }
};