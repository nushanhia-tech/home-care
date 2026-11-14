export class ApiError extends Error{constructor(message:string,public status=400,public details:Record<string,unknown>={}){super(message)}}
