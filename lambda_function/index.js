const AWS = require("aws-sdk");
const s3 = new AWS.S3();

exports.handler = async (event) => {
  try {
    const body = JSON.parse(event.body);
    const { fileName, fileType } = body;

    const params = {
      Bucket: process.env.BUCKET_NAME,
      Key: fileName,
      Expires: 300,
      ContentType: fileType,
    };

    const uploadURL = await s3.getSignedUrlPromise("putObject", params);

    return {
      statusCode: 200,
      body: JSON.stringify({ uploadURL }),
      headers: {
        "Access-Control-Allow-Origin": "*", 
        "Content-Type": "application/json" 
      }
    };
  } catch (error) {
    return {
      statusCode: 500,
      body: JSON.stringify({ message: "Error generating presigned URL" }),
      headers: {
        "Access-Control-Allow-Origin": "*", 
        "Content-Type": "application/json" 
      }
    };
  }
};
