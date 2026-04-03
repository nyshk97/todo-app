export interface Todo {
  id: string;
  title: string;
  date: string; // YYYY-MM-DD
  completed: boolean;
  position: number;
  carried_over: boolean;
  completed_at: string | null;
  duration: number | null; // 所要時間（分）。null = 未設定
  created_at: string;
  updated_at: string;
}

export interface CreateTodoRequest {
  title: string;
}

export interface UpdateTodoRequest {
  title?: string;
  completed?: boolean;
  position?: number;
  duration?: number | null;
}

export interface ReorderRequest {
  items: { id: string; position: number }[];
}

export interface TodosResponse {
  todos: Todo[];
  date: string;
  editable: boolean;
}
