// --- Projects ---

export interface Project {
  id: string;
  name: string;
  position: number;
  created_at: string;
  updated_at: string;
}

export interface CreateProjectRequest {
  name: string;
}

export interface UpdateProjectRequest {
  name?: string;
  position?: number;
}

// --- Sections ---

export interface Section {
  id: string;
  project_id: string;
  name: string;
  position: number;
  created_at: string;
  updated_at: string;
}

export interface CreateSectionRequest {
  name: string;
}

export interface UpdateSectionRequest {
  name?: string;
  position?: number;
}

// --- Tasks ---

export interface Task {
  id: string;
  project_id: string;
  section_id: string | null;
  title: string;
  due_date: string | null; // YYYY-MM-DD
  position: number;
  comment_count: number;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface CreateTaskRequest {
  title: string;
  project_id: string;
  section_id?: string | null;
  due_date?: string | null;
}

export interface UpdateTaskRequest {
  title?: string;
  project_id?: string;
  section_id?: string | null;
  due_date?: string | null;
  position?: number;
}

export interface ReorderRequest {
  items: { id: string; position: number; section_id?: string | null }[];
}

// --- Comments ---

export interface Comment {
  id: string;
  task_id: string;
  content: string;
  attachments: Attachment[];
  created_at: string;
  updated_at: string;
}

export interface CreateCommentRequest {
  content: string;
}

export interface UpdateCommentRequest {
  content: string;
}

// --- Attachments ---

export interface Attachment {
  id: string;
  comment_id: string;
  filename: string;
  content_type: string;
  size: number;
  created_at: string;
}

// --- API Responses ---

export interface ProjectWithDetails extends Project {
  sections: Section[];
  tasks: Task[];
}

export interface UpcomingTask extends Task {
  project_name: string;
}

export interface ArchivedTask extends Task {
  project_name: string;
}
