import { MongoClient, ServerApiVersion } from "mongodb";

// Read connection string from environment variable with fallback
const URI = process.env.MONGODB_URI || "mongodb://mongodb:27017";  // I added Environment which can now work anywhere! Updated for both AKS and local Docker
const DB_NAME = process.env.DB_NAME || "employees";

// Cosmos DB specific options
const client = new MongoClient(URI, {
  ssl: true,   // Cosmos DB requires SSL
  retryWrites: false,  // Cosmos DB doesn't support retryable writes
  // Remove serverApi - Cosmos DB doesn't support it
});

async function connectDB() {
  try {
    await client.connect();
    console.log("Successfully connected to Cosmos DB!");
  } catch (err) {
    console.error("Cosmos DB connection error:", err);
    process.exit(1); // Exit if can't connect to DB
  }
}

// Connect when module loads
connectDB();

let db = client.db(DB_NAME);

export default db;